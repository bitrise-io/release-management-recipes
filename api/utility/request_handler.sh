#!/bin/bash
#
# Common utility functions for request handling.

#######################################
# Checks for a request error coming from Release Management Public API.
# Globals:
#   None
# Arguments:
#   A JSON object with keys `response_body` and `http_code` (created by makeFullResponse())
# Outputs:
#   Returns the error if there is an error.
request_error() {
  local body=$(getBodyFromFullResponse "$1")
  local http_code=$(getHttpStatusFromFullResponse "$1")

  local endpointName="$2"
  local non200=0
  local hasResponseErr=0

  if [[ $http_code -lt 200 || $http_code -ge 300 ]]; then
    non200=1
    echo "Error: ${endpointName} request failed with status $http_code" >&2
  fi
  
  error_code=$(echo "$body" | jq '.code' )
  if [[ -n "$error_code" && "$error_code" != "null" ]]; then
    hasResponseErr=1
    echo "$body" | jq .
  fi

  if [[ $hasResponseErr -eq 1 || $non200 -eq 1 ]]; then
    exit 1
  fi
}

#######################################
# Gets response body from makeFullResponse() json object
# Globals:
#   None
# Arguments:
#   A JSON object with keys `response_body` and `http_code` (created by makeFullResponse())
# Outputs:
#   A JSON object with the response body
getBodyFromFullResponse() {
  local full_response=$1
  echo "$full_response" | jq ".response_body  // empty"
}

#######################################
# Gets response body from makeFullResponse() json object
# Globals:
#   None
# Arguments:
#   A JSON object with keys `response_body` and `http_code` (created by makeFullResponse())
# Outputs:
#   A string with the http status code of the response
getHttpStatusFromFullResponse() {
  local full_response=$1
  echo "$full_response" | jq ".http_code"
}

#######################################
# Combines the HTTP response code and response body into a json object
# Globals:
#   None
# Arguments:
#   The response body.
#   The http code (int)
# Outputs:
#   A JSON object with format {"http_code": <int>, "response_body": <string>}
makeFullResponse() {
  local body=$1
  local http_code=$2

  if [[ -z "$body" ]]; then
    jq -n --argjson http_code "$http_code" \
      '{"http_code": $http_code}'
  else
    jq -n --argjson body "$body" --argjson http_code "$http_code" \
      '{"http_code": $http_code, "response_body": $body}'
  fi
}