#!/bin/bash
# shellcheck disable=SC1091

# set to 0 for less output, set to 2 for a lot of output, set to 1 for something in between
DEBUG=1

set -euo pipefail
if [[ "$DEBUG" -ge 1 ]]; then
    set -o xtrace # extra verbose for debugging
fi

DO_LOOP=0
if [[ "${1:-}" = "--infinite-loop" ]]; then
    DO_LOOP=1
    shift
fi

# repo owner and repo name - required, intentionally no default
REPO_OWNER=
REPO_NAME=
# API authorization token, see https://developer.github.com/v3/#authentication
# - required but intentionally left blank
AUTHORIZATION=
# branches/refs to watch for status - one or more, space-separated
# - for multiple branches, the entire set must be quoted, e.g. "devel foo/bar alpha"
REFS="master"

# USB device identifier
# - optional but recommended; if unspecified, all matching hubs will be switched
# - many motherboards feature switchable hubs, unplugging your input devices is undesirable
# - this filters by the device's self-identification
USB_DEVICE_ID="05e3:0608"
# device location (reported by uhubctl in "Current status for hub 2-1.1")
# - optional but recommended; if unspecified, all matching hubs will be switched
# - same switchable chipsets appear in many end devices
# - this filters by physical topology
USB_DEVICE_LOCATION=""

# Hub port to switch (optional)
# - setting to empty or "any" will toggle all ports
# - setting the port number to "-" (hyphen) disables switching of this type (success/failure)
# (e.g. in my first setup, only the failure light was present)
# Here, we use one port for a "success" light...
USB_PORT_SUCCESS="3"
# ... and another for a "failure" light.
USB_PORT_FAILURE="4"
# uhubctl executable, Magic Happens Here - get the source at https://github.com/mvp/uhubctl
UHUBCTL="$(which uhubctl)"
# jq, a JSON command line processor
JQ="$(which jq)"
# if array result, get the newest non-pending part, return state; if single result, return its state.
JQ_SCRIPT='if . | type == "array" then map(select (.state != "pending")) | max_by(.updated_at) | .state else .state end'
# cURL, a data transfer tool - used for HTTPS requests here.
CURL="$(which curl)"

# time in seconds to wait for the API response
REQUEST_TIMEOUT="5"
# if the request doesn't return data, retry via proxy (if any)
FALLBACK_PROXY=""
# time to wait for the API response when going through proxy - set this to a larger value, as this is already a fallback
FALLBACK_PROXY_REQUEST_TIMEOUT="30"
# delay between API requests
DELAY_SECONDS="300"

# override the above defaults
# - also prevent *your own* authorization token from being stored in git
# - custom settings belong *there*
# - see buildenlights.rc.example
source ./buildenlights.rc

if [[ -z "$REPO_OWNER" ]] || [[ -z "$REPO_NAME" ]] || [[ -z "$REFS" ]] || [[ -z "$AUTHORIZATION" ]]; then
    echo "Config required in buildenlights.rc, none of the following can be empty:"
    echo "OWNER: $REPO_OWNER"
    echo "REPO: $REPO_NAME"
    echo "BRANCH: $REFS"
    echo "AUTHORIZATION: $AUTHORIZATION"
    exit 1
fi

# this is a hard requirement
# - everything else can be replaced or worked around
if [[ ! -x "${UHUBCTL}" ]]; then
    echo "Cannot find uhubctl executable."
    exit 2
fi

# enable the success light
success_on() {
    __uhubctl_call 1 "${USB_PORT_SUCCESS}"
}
# disable the success light
success_off() {
    __uhubctl_call 0 "${USB_PORT_SUCCESS}"
}
# enable the failure light
fail_on() {
    __uhubctl_call 1 "${USB_PORT_FAILURE}"
}
# disable the failure light
fail_off() {
    __uhubctl_call 0 "${USB_PORT_FAILURE}"
}

# all uhubctl interaction happens here
__uhubctl_call() {
    ACTION="${1}"
    if [[ -z "${2:-}" ]] || [[ "${2}" = "any" ]] ; then
        # toggle all ports
        PORTS=()
    else
        if [[ "${2}" = "-" ]]; then
            # ignore this call
            return
        fi
        PORTS=(--ports ${2})
    fi
    # do not exit on error here (e.g. no hubs matched)
    # be more verbose if debug 2
    if [[ "$DEBUG" -lt 2 ]]; then
        "${UHUBCTL}" --vendor "${USB_DEVICE_ID}" --loc "${USB_DEVICE_LOCATION}" --action "${ACTION}" "${PORTS[@]}" &> /dev/null || true
    else
        "${UHUBCTL}" --vendor "${USB_DEVICE_ID}" --loc "${USB_DEVICE_LOCATION}" --action "${ACTION}" "${PORTS[@]}" || true
    fi
}

# request the ref status from GH
# note that a response could be a single result or multiple
#  - in that case, use the latest
__api_status_call() {
    FALLBACK="${1}"
    URL="${2}"
    if [[ "${FALLBACK}" -eq 0 ]]; then
        TIMEOUT="${REQUEST_TIMEOUT}"
        PROXY=()
    else
        TIMEOUT="${FALLBACK_PROXY_REQUEST_TIMEOUT}"
        PROXY=(--proxy ${FALLBACK_PROXY})
    fi

    if [[ "$DEBUG" -ge 2 ]]; then
        STATUS_DATA=$(timeout "${TIMEOUT}" "${CURL}" "${PROXY[@]}" -H "Authorization: ${AUTHORIZATION}" "${URL}" -q || true)
        echo "${STATUS_DATA}" > /dev/stderr
        echo "${STATUS_DATA}" \
        | ${JQ} --raw-output "${JQ_SCRIPT}"
    else
        (timeout "${TIMEOUT}" "${CURL}" "${PROXY[@]}" -H "Authorization: ${AUTHORIZATION}" "${URL}" -q \
        | ${JQ} --raw-output "${JQ_SCRIPT}" || true)
    fi
}

__api_status_finished() {
    # called when all the API calls finish, SUCCESS_STATE is passed to reflect the content of the calls

    # we currently ignore SUCCESS_STATE in $1, just wait for next run.
    echo "sleep ${DELAY_SECONDS}..."
    sleep "${DELAY_SECONDS}" || true
}

__api_status_error() {
    # called when the API itself is in an error state, e.g. returning unicorns or when network breaks

    # we currently only wait longer for next run - we could e.g. try to recover, or quit by setting DO_LOOP=0
    LONGER_SLEEP=$(( DELAY_SECONDS * 10 ))
    echo "Fetching status has failed, sleeping for ${LONGER_SLEEP} seconds"
    sleep "${LONGER_SLEEP}" || true
}

SUCCESS=0
while true; do
    BUILD_FAIL_COUNT=0
    SECONDS=0
    for BRANCH in ${REFS}; do
        # see https://developer.github.com/v3/repos/statuses/
        URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits/${BRANCH}/status"

        FALLBACK=0
        BUILD_STATUS=$(__api_status_call ${FALLBACK} "${URL}") || FALLBACK=1
        if [[ -z "${BUILD_STATUS}" ]]; then
            FALLBACK=1
        fi

        if [[ ${FALLBACK} -gt 0 ]] && [[ "${FALLBACK_PROXY:-}" != "" ]]; then
            echo "Failed, retrying with ${FALLBACK_PROXY}"
            BUILD_STATUS=$(__api_status_call ${FALLBACK} "${URL}") || FALLBACK=2
        fi
        if [[ -z "${BUILD_STATUS}" ]]; then
            # even the fallback has failed, handle
            FALLBACK=2
            break
        fi
        if [[ "$BUILD_STATUS" = "failure" ]] || [[ "$BUILD_STATUS" = "error" ]]; then
            BUILD_FAIL_COUNT=$(( BUILD_FAIL_COUNT + 1 ))
        fi
    done


    if [[ "${FALLBACK}" -lt 2 ]]; then
        echo "${SECONDS} seconds wall time"
        echo "Result: ${BUILD_STATUS}"
        if [[ "$BUILD_FAIL_COUNT" -eq 0 ]]; then
            # disable failure light, enable success light
            fail_off
            success_on
            SUCCESS=1
        elif [[ "${BUILD_STATUS}" = "failure" ]] || [[ "${BUILD_STATUS}" = "error" ]]; then
            # disable success light, enable failure light
            success_off
            fail_on
            SUCCESS=0
        else
            # unrecognized state (e.g. pending?), disable both lights
            success_off
            fail_off
        fi

        # pass the last known success state and current build status
        __api_status_finished "${SUCCESS}"

    else
        # error state (e.g. API not responding?), disable both lights and try to recover
        success_off
        fail_off
        __api_status_error "${SUCCESS}"
    fi

    # we can quit the script by setting this variable to 0, e.g. in a handler
    if [[ "${DO_LOOP}" -eq 0 ]]; then
        break;
    fi
done
