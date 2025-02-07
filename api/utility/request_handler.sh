#!/bin/bash
#
# Common utility functions for request handling.

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

  echo "$1" | jq .

  exit 0
}
