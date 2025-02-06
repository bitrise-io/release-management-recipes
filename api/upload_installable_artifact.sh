#!/bin/bash
#
# Uploads an installable artifact to Bitrise using Release Management Public API.
# Reference: https://api.bitrise.io/release-management/api-docs/index.html#/Installable%20Artifacts%20-%20COMING%20SOON/GenerateInstallableArtifactUploadUrl
#
# This script supports Linux distributions (alpine, arch, centos, debian, fedora, rhel, ubuntu) and macOS.
# For it to work properly you will need either jq and openssl packages installed on your system or sudo privileges for the script.
#
# You need a couple of environment variables to set up and you can call this script from terminal:
# ARTIFACT_PATH=LOCAL_PATH_OF_THE_ARTIFACT_TO_BE_UPLOADED \
# AUTHORIZATION_TOKEN=BITRISE_RM_API_ACCESS_TOKEN \
# CONNECTED_APP_ID=APP_ID_OF_THE_CONNECTED_APP_THE_ARTIFACT_WILL_BE_UPLOADED_TO \
# /bin/bash ./scripts/upload_installable_artifact.sh

#######################################
# Checks for script dependencies. If the OS is not supported it exits. Missing dependencies (jq, openssl) are installed.
# Globals:
#   None
# Arguments:
#   None
#######################################
check_dependencies() {
  if [[ is_macOS -eq 1 ]] && [[ linux_distro -eq 1 ]]; then
    echo "Unsupported OS. Exiting..."
    exit 1
  fi

  if [[ $(check_command_installed "jq") -eq 1 ]]; then
      install_command "jq"
  fi

  if [[ $(check_command_installed "openssl") -eq 1 ]]; then
      install_command "openssl"
  fi
}

#######################################
# Checks Whether the given command is installed or not.
# Globals:
#   None
# Arguments:
#   The command to check for.
# Outputs:
#   Returns zero if the command is installed and 1 if not.
#######################################
check_command_installed() {
    if command -v "$1" > /dev/null 2>&1; then
        echo 0
    else
        echo 1
    fi
}

#######################################
# Gets the information needed for uploading an installable artifact from Release Management Public API.
# Globals:
#   AUTHORIZATION_TOKEN
#   ARTIFACT_PATH
#   CONNECTED_APP_ID
# Arguments:
#   UUID for the artifact to be uploaded.
# Outputs:
#   Returns the upload information including headers, method and url.
#######################################
get_upload_information() {
  if [[ linux_distro -eq 1 ]]; then
    file_size_bytes=$(stat -c%s "$ARTIFACT_PATH")
  else
    file_size_bytes=$(stat -f%z "$ARTIFACT_PATH")
  fi

  file_name=$(echo "\"$ARTIFACT_PATH\"" | jq -r 'split("/") | .[-1]')

  upload_info=$(curl -s -H "Authorization: $AUTHORIZATION_TOKEN" "$RM_API_HOST/release-management/v1/connected-apps/$CONNECTED_APP_ID/installable-artifacts/$1/upload-url?file_name=$file_name&file_size_bytes=$file_size_bytes")

  echo "$upload_info"
}

#######################################
# Installs a missing command to the machine.
# Globals:
#   None
# Arguments:
#   The command to be installed.
#######################################
install_command() {
     if [[ is_macOS -eq 0 ]]; then
         if command -v brew > /dev/null 2>&1; then
             brew install "$1"
         else
             echo "Homebrew is not installed. Please install Homebrew first."
             exit 1
         fi
     else
        distro=$(linux_distro)
        println "Detected Linux distribution: ${distro}.\n"

        case "$distro" in
          ubuntu|debian)
            sudo apt update && sudo apt install -y "$1"
            ;;
          fedora)
            sudo dnf install -y "$1"
            ;;
          centos|rhel)
            sudo yum install -y "$1"
            ;;
          alpine)
            sudo apk add --no-cache "$1"
            ;;
          arch)
            sudo pacman -Sy "$1"
            ;;
      esac
     fi
 }

#######################################
# Checks whether the script is running on MacOS or not.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Returns zero if MacOS found, 1 otherwise.
#######################################
is_macOS() {
  if [ "$(uname)" == "Darwin" ]; then
    return 0
  else
    return 1
  fi
}

#######################################
# Continuously checks whether the already uploaded artifact is processed by Release Management or not.
# After successful processing, you can use the uploaded artifact in your releases and test distributions.
# The function returns with a failure after a pre-defined retry count.
# This is a recursive function calling itself four times after the first try.
# Globals:
#   AUTHORIZATION_TOKEN
#   CONNECTED_APP_ID
# Arguments:
#   UUID for the artifact to be uploaded.
#   Retry count.
#######################################
is_processed() {
  if [[ $2 == 4 ]]; then
    echo "The artifact is still not processed after $2 retries. Exiting..."

    exit 1
  fi

  status_data=$(curl -s -H "Authorization: $AUTHORIZATION_TOKEN" "$RM_API_HOST/release-management/v1/connected-apps/$CONNECTED_APP_ID/installable-artifacts/$1/status")

  request_error "$status_data"

  status=$(echo "$status_data" | jq -r '.status')
  if [[ "$status" == "processed_valid" ]] || [[ "$status" == "processed_invalid" ]]; then
    echo "$status_data"

    exit 0
  elif [[ "$status" == "uploaded" ]] || [[ "$status" == "upload_requested" ]]; then
    echo "$status_data"

    sleep 1
    is_processed "$1" $2 + 1
  else
    echo "Unexpected status: $status. Exiting..."

    exit 1
  fi
}

#######################################
# Checks the Linux distribution the script is running on.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Returns the id of the OS distribution and zero if a supported distribution is found. Returns 1 if not a Linux.
#######################################
linux_distro() {
  if [ -f /etc/os-release ]; then
    id=$(cat "/etc/os-release")
    case "$id" in ubuntu|debian|fedora|centos|rhel|alpine|arch)
      echo "$id"
      return 0
      ;;
    *)
      echo "Unsupported Linux distribution. Exiting..."
      exit 1
      ;;
    esac
  else
    return 1
  fi
}

#######################################
# Processes the response of Google Cloud Storage when the upload request has been sent.
# Globals:
#   None
# Arguments:
#   The upload response.
#   The artifact UUID used for uploading.
# Outputs:
#   Returns upload http status and response body from the upload request.
process_upload_response() {
  http_status_code="${1:${#1}-3}"
  if [[ "$http_status_code" == 200 ]]; then
    is_processed "$2" 0
  else
    response_body="${1:0:${#1}-3}"

    printf "upload http status: %s\n" "$http_status_code"
    echo "$response_body"
  fi
}

#######################################
# Checks for a request error coming from Release Management Public API.
# Globals:
#   None
# Arguments:
#   The response body.
# Outputs:
#   Returns the error if there is an error.
request_error() {
  error_code=$(echo "$1" | jq '.code' )
  if [ "$error_code" == "null" ]; then
    return
  fi

  echo "$1"

  exit 0
}

#######################################
# Uploads the installable artifact to Google Cloud Storage using the information given by Release Management Public API.
# Globals:
#   The artifact path which contains the file to be uploaded.
# Arguments:
#   The upload information given by Release Management Public API.
# Outputs:
#   Returns the response of Google Cloud Storage.
upload_artifact() {
  headers_json=$(echo "$1" | jq -r '.headers | to_entries | map("\(.value.name): \(.value.value)")')
  method=$(echo "$1" | jq -r '.method')
  url=$(echo "$1" | jq -r '.url')

  # read headers into bash array from jq array
  headers=()
  while IFS= read -r line; do
    headers+=($line)
  done <<< "$headers_json"

  # sanitize headers
  for ((i = 0; i < ${#headers[@]}; i++)); do
    headers[i]="${headers[i]//\"/}"
    headers[i]="${headers[i]%,}"
  done

  # build curl command
  curl_command="curl -sw \"%{http_code}\" -o - -X \"$method\""
  for ((i = 1; i + 1 < ${#headers[@]}; i+=2)); do
    curl_command+=" -H \"${headers[i]} ${headers[i+1]}\""
  done
  curl_command+=" --upload-file \"$ARTIFACT_PATH\" \"$url\""

  eval "$curl_command"
}

check_dependencies

uuid=$(openssl rand -hex 16)
installable_artifact_id=${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20:12}

if [ -z "$RM_API_HOST" ]; then
  RM_API_HOST="https://api.bitrise.io"
fi

upload_info=$(get_upload_information "$installable_artifact_id")
request_error "$upload_info"
upload_response=$(upload_artifact "$upload_info")
process_upload_response "$upload_response" "$installable_artifact_id"
