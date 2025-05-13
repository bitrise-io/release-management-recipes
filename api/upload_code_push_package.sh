#!/bin/bash
#
# Uploads a CodePush package to Bitrise using Release Management Public API.
# Reference: https://api.bitrise.io/release-management/api-docs/index.html#
#
# This script supports Linux distributions (alpine, arch, centos, debian, fedora, rhel, ubuntu) and macOS.
# For it to work properly you will need either jq and openssl packages installed on your system or sudo privileges for the script.
#
# You need a couple of environment variables to set up and you can call this script from terminal:
# PACKAGE_PATH=LOCAL_PATH_OF_THE_PACKAGE_TO_BE_UPLOADED \
# AUTHORIZATION_TOKEN=BITRISE_RM_API_ACCESS_TOKEN \
# CONNECTED_APP_ID=APP_ID_OF_THE_CONNECTED_APP_THE_PACKAGE_WILL_BE_UPLOADED_TO \
# DEPLOYMENT_ID=DEPLOYMENT_ID_WITHIN_THE_CONNECTED_APP_THE_PACKAGE_WILL_BE_UPLOADED TO \
# APP_VERSION=1.1.0
# /bin/bash ./scripts/upload_code_push_package.sh

# Includes dependency installer and request handler utilities.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/utility/install_dependencies.sh"
. "$SCRIPT_DIR/utility/request_handler.sh"

#######################################
# Checks for script dependencies. Missing dependencies (curl, jq, openssl) are installed.
# Globals:
#   None
# Arguments:
#   None
#######################################
check_dependencies() {
  if [[ $(check_command_installed "curl") -eq 1 ]]; then
    install_command "curl"
  fi

  if [[ $(check_command_installed "jq") -eq 1 ]]; then
    install_command "jq"
  fi

  if [[ $(check_command_installed "openssl") -eq 1 ]]; then
    install_command "openssl"
  fi
}

#######################################
# Gets the information needed for uploading an package from Release Management Public API.
# Globals:
#   AUTHORIZATION_TOKEN
#   PACKAGE_PATH
#   CONNECTED_APP_ID
#   DEPLOYMENT_ID
# Arguments:
#   UUID for the package to be uploaded.
# Outputs:
#   Returns the upload information including headers, method and url.
#######################################
get_upload_information() {
  if [[ $(linux_distro) -ne 1 ]]; then
    file_size_bytes=$(stat -c%s "$PACKAGE_PATH")
  else
    file_size_bytes=$(stat -f%z "$PACKAGE_PATH")
  fi

  file_name=$(echo "\"$PACKAGE_PATH\"" | jq -r 'split("/") | .[-1]')
  response_body=$(mktemp)
  http_code=$(curl -w "%{http_code}" -s -H "Authorization: $AUTHORIZATION_TOKEN" -o "$response_body" "$RM_API_HOST/release-management/v1/connected-apps/$CONNECTED_APP_ID/code-push/deployments/$DEPLOYMENT_ID/packages/$1/upload-url?file_name=$file_name&file_size_bytes=$file_size_bytes&app_version=$APP_VERSION")
  upload_info=$(<"$response_body")
  rm -f "$response_body"

  makeFullResponse "$http_code" "$upload_info"
}

#######################################
# Continuously checks whether the already uploaded artifact is processed by Release Management or not.
# After successful processing, you can use the uploaded artifact in your releases and test distributions.
# The function returns with a failure after a pre-defined retry count.
# This is a recursive function calling itself four times after the first try.
# Globals:
#   AUTHORIZATION_TOKEN
#   CONNECTED_APP_ID
#   DEPLOYMENT_ID
# Arguments:
#   UUID for the package to be uploaded.
#   Retry count.
#######################################
is_processed() {
  if [[ $2 == 4 ]]; then
    echo "The package is still not processed after $2 retries. Exiting..."

    exit 1
  fi

  response_body=$(mktemp)
  http_code=$(curl -s -w "%{http_code}" -H "Authorization: $AUTHORIZATION_TOKEN" -o "$response_body" "$RM_API_HOST/release-management/v1/connected-apps/$CONNECTED_APP_ID/code-push/deployments/$DEPLOYMENT_ID/packages/$1/status")
  status_data=$(<"$response_body")
  rm -f "$response_body"

  fullResponse=$(makeFullResponse "$http_code" "$status_data")
  request_error "$fullResponse" "/installable-artifacts/$1/status"

  status=$(echo "$status_data" | jq -r '.status')
  if [[ "$status" == "processed_valid" ]] || [[ "$status" == "processed_invalid" ]]; then
    echo "$status_data"

    exit 0
  elif [[ "$status" == "created" ]] || [[ "$status" == "uploaded" ]] || [[ "$status" == "upload_requested" ]]; then
    echo "$status_data"

    sleep 1
    is_processed "$1" $2 + 1
  else
    echo "Unexpected status: $status. Exiting..."

    exit 1
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
    printf "upload http status: %s\n" "$http_status_code"
    echo "${1}" | jq .
    exit 1
  fi
}

#######################################
# Uploads the package to Google Cloud Storage using the information given by Release Management Public API.
# Globals:
#   The package path which contains the file to be uploaded.
# Arguments:
#   The upload information given by Release Management Public API.
# Outputs:
#   Returns the response of Google Cloud Storage.
upload_package() {
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
  curl_command+=" --upload-file \"$PACKAGE_PATH\" \"$url\""

  eval "$curl_command"
}

check_dependencies

uuid=$(openssl rand -hex 16)
package_id=${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20:12}

if [ -z "$RM_API_HOST" ]; then
  RM_API_HOST="https://api.bitrise.io"
fi

upload_info_full_resp=$(get_upload_information "$package_id")
request_error "$upload_info_full_resp" '/code-push/deployments/$DEPLOYMENT_ID/packages/$1/upload-url'
upload_info=$(getBodyFromFullResponse "$upload_info_full_resp")
upload_response=$(upload_package "$upload_info")
process_upload_response "$upload_response" "$package_id"
