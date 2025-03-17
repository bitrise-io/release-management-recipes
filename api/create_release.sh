#!/bin/bash
#
# Creates a release under the given connected app.
# Reference: https://api.bitrise.io/release-management/api-docs/index.html#/Releases/CreateRelease
#
# You need a couple of environment variables to set up and you can call this script from the terminal:
# AUTHORIZATION_TOKEN=BITRISE_RM_API_ACCESS_TOKEN \
# CONNECTED_APP_ID=APP_ID_OF_THE_CONNECTED_APP \
# RELEASE_NAME=THE_NAME_OF_THE_RELEASE_TO_BE_CREATED \
# /bin/bash ./create_release.sh

# Includes dependency installer and request handler utilities.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/utility/install_dependencies.sh"
. "$SCRIPT_DIR/utility/request_handler.sh"

#######################################
# Checks for script dependencies. Missing dependencies (jq, curl) are installed.
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
}

#######################################
# Creates a release under the given connected app.
# Globals:
#   AUTHORIZATION_TOKEN
#   CONNECTED_APP_ID
#   RELEASE_NAME
#   RM_API_HOST
# Outputs:
#   Returns the created release.
#######################################
create_release() {
  
  response_body=$(mktemp)
  http_code=$(curl -s -w "%{http_code}" -H "Authorization: $AUTHORIZATION_TOKEN" -H "Content-Type: application/json" -X "POST" -o "$response_body" "$RM_API_HOST/release-management/v1/releases" -d "{\"connected_app_id\": \"$CONNECTED_APP_ID\", \"name\": \"$RELEASE_NAME\"}")
  release=$(<"$response_body")
  rm -f "$response_body"

  makeFullResponse "$upload_info" "$http_code"
}

#######################################
# Processes the response of the Release Management API when the create release request has been answered.
# Globals:
#   None
# Arguments:
#   The upload response.
# Outputs:
#   Returns upload http status and response body from the upload request.
process_create_release_response() {
  local http_status=$(getHttpStatusFromFullResponse "$1")
  printf "upload http status: %s" "$http_status"

  local body=$(getBodyFromFullResponse "$1")
  if [[ -n "$body" ]]; then
    echo "${body}" | jq .
  fi
  
}

check_dependencies

if [ -z "$RM_API_HOST" ]; then
  RM_API_HOST="https://api.bitrise.io"
fi

release_full_resp=$(create_release)
request_error "$release_full_resp" '/releases'
process_create_release_response  "$release_full_resp"
