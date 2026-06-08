#!/bin/bash
#
# Uploads a CodePush update to Bitrise using Release Management Public API.
# Reference: https://api.bitrise.io/release-management/api-docs/index.html?urls.primaryName=RM%20CodePush%20API%20V2.1#/Updates/GetCodePushUpdateUploadUrl
#
# This script supports Linux distributions (alpine, arch, centos, debian, fedora, rhel, ubuntu) and macOS.
# For it to work properly you will need either jq and openssl packages installed on your system or sudo privileges for the script.
#
# You need a couple of environment variables to set up and you can call this script from terminal:
# UPDATE_PATH=LOCAL_PATH_OF_THE_UPDATE_TO_BE_UPLOADED \
# AUTHORIZATION_TOKEN=BITRISE_RM_API_ACCESS_TOKEN \
# DEPLOYMENT_ID=DEPLOYMENT_ID_WITHIN_THE_CONNECTED_APP_THE_UPDATE_WILL_BE_UPLOADED TO \
# APP_VERSION=1.1.0
# ROLLOUT=100
# IS_DISABLED=false
# IS_MANDATORY=false
# DESCRIPTION=example text
# /bin/bash ./scripts/upload_code_push_package.sh

if [ -z "${ROLLOUT}" ]; then
    ROLLOUT_PERCENTAGE='100'
else
    ROLLOUT_PERCENTAGE=${ROLLOUT}
fi

if [ -z "${IS_DISABLED}" ]; then
    DISABLED=false
else
    DISABLED=${IS_DISABLED}
fi

if [ -z "${IS_MANDATORY}" ]; then
    MANDATORY=false
else
    MANDATORY=${IS_MANDATORY}
fi

if [ -z "${DESCRIPTION}" ]; then
    DESCRIPTION=""
else
    DESCRIPTION=$(echo ${DESCRIPTION}|jq -sRr @uri)
fi

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
# Gets the information needed for uploading an update from Release Management Public API.
# Globals:
#   AUTHORIZATION_TOKEN
#   UPDATE_PATH
#   DEPLOYMENT_ID
# Arguments:
#   UUID for the update to be uploaded.
# Outputs:
#   Returns the upload information including headers, method and url.
#######################################
get_upload_information() {
  if [[ $(linux_distro) -ne 1 ]]; then
    file_size_bytes=$(stat -c%s "$UPDATE_PATH")
  else
    file_size_bytes=$(stat -f%z "$UPDATE_PATH")
  fi

  file_name=$(echo "\"$UPDATE_PATH\"" | jq -r 'split("/") | .[-1]')
  response_body=$(mktemp)
  http_code=$(curl -X GET -w "%{http_code}" -s -H "Authorization: $AUTHORIZATION_TOKEN" -o "$response_body" "$RM_API_HOST/release-management/v2/code-push/v1/updates/$1/upload-url?deployment_id=$DEPLOYMENT_ID&file_name=$file_name&file_size_bytes=$file_size_bytes&app_version=$APP_VERSION&description=$DESCRIPTION&rollout=$ROLLOUT_PERCENTAGE&disabled=$DISABLED&mandatory=$MANDATORY")
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
#   DEPLOYMENT_ID
# Arguments:
#   UUID for the update to be uploaded.
#   Retry count.
#######################################
is_processed() {
  if [[ $2 == 10 ]]; then
    echo "The update is still not processed after $2 retries. Exiting..."

    exit 1
  fi

  response_body=$(mktemp)
  http_code=$(curl -s -w "%{http_code}" -H "Authorization: $AUTHORIZATION_TOKEN" -o "$response_body" "$RM_API_HOST/release-management/v2/code-push/v1/updates/$1/status")
  status_data=$(<"$response_body")
  rm -f "$response_body"

  fullResponse=$(makeFullResponse "$http_code" "$status_data")
  request_error "$fullResponse" "/updates/$1/status"

  status=$(echo "$status_data" | jq -r '.status')
  if [[ "$status" == "processed_valid" ]] || [[ "$status" == "processed_invalid" ]]; then
    echo "$status_data"

    exit 0
  elif [[ "$status" == "created" ]] || [[ "$status" == "uploaded" ]] || [[ "$status" == "upload_requested" ]]; then
    echo "$status_data"

    sleep 2
    is_processed "$1" $(($2 + 1))
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
# Uploads the update to Google Cloud Storage using the information given by Release Management Public API.
# Globals:
#   The update path which contains the file to be uploaded.
# Arguments:
#   The upload information given by Release Management Public API.
# Outputs:
#   Returns the response of Google Cloud Storage.
upload_update() {
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
  curl_command+=" --upload-file \"$UPDATE_PATH\" \"$url\""

  eval "$curl_command"
}

check_dependencies

uuid=$(openssl rand -hex 16)
update_id=${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20:12}

if [ -z "$RM_API_HOST" ]; then
  RM_API_HOST="https://api.bitrise.io"
fi

upload_info_full_resp=$(get_upload_information "$update_id")
request_error "$upload_info_full_resp" '/code-push/updates/$1/upload-url'
upload_info=$(getBodyFromFullResponse "$upload_info_full_resp")
upload_response=$(upload_update "$upload_info")
process_upload_response "$upload_response" "$update_id"
