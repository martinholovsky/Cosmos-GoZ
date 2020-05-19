#!/usr/bin/env bash

#: title: GoZ Phase 1/a/b Update Client
#: file: goz-updateclient.sh
#: desc: Update Client-ID on path so trust period will not expire
#: author: Martin Holovsky - github.com/martinholovsky
#: usage: goz-updateclient.sh update [path-name]
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

##############################################################################
#
# VARIABLES
#
##############################################################################

# How many seconds before trust expiration you want to execute client-update
# Default is 99 seconds before expiration of trust-period
# You can set this variable during script execution$ RISKAPPETITE=99 script.sh
RISKAPPETITE=${RISKAPPETITE:-"99"}

#color codes
txtred='\e[0;31m'
txtblue='\e[1;34m'
txtgreen='\e[0;32m'
txtwhite='\e[0;37m'
txtdefault='\e[00m'
txtyellow='\e[0;33m'

##############################################################################
#
# TRAP
#
##############################################################################

# end script in case of error
# exception: if statement, until and while loop, logical AND (&&) or OR (||)
# trap also those exit signals: 1/HUP, 2/INT, 3/QUIT, 15/TERM, ERR
trap exit_on_error 1 2 3 15 ERR

exit_on_error() {
    local exit_status=${1:-$?}
    echo -e "${txtred}--- Exiting ${0} with status: ${exit_status} ${txtdefault}"
    echo "--- Error occured ($(date '+%F %T')) in ${0} with status/on line: ${exit_status}; parent process: ${$} ($(cat /proc/$$/cmdline)); pipe: ${PIPESTATUS}; ssh client: ${SSH_CLIENT}"
    if [ -d "/var/goz-temp.${TEMPDIR##*.}" ]; then
      rm -rf "/var/goz-temp.${TEMPDIR##*.}"
    fi
    exit "${exit_status}"
}

##############################################################################
#
# FUNCTIONS
#
##############################################################################

f_msg() {
    #example: f_msg info "This is info message"
    case "${1}" in
        error) echo -e "${txtred}$(date) -- ${2} ${txtdefault}" ;;
        warn) echo -e "${txtyellow}$(date) -- ${2} ${txtdefault}" ;;
        info) echo -e "${txtgreen}$(date) -- ${2} ${txtdefault}" ;;
        newline) echo "" ;;
        *) echo "${1} ${2}" ;;
    esac
}

f_mktemp() {
    #example: f_mktemp
    #creates temp dir, temp files should be inside
    TEMPDIR="$(mktemp -d /tmp/goz-temp.XXXXXXXXXXXXXXXXXX${RANDOM}${RANDOM})"
    TMPDIR="${TEMPDIR}"
}

f_updateclient() {

  #lets make temp folder
  f_mktemp
  cd "${TEMPDIR}"
  #get variables from path name
  PATHSHOW=$(rly paths show ${PATHNAME} > path)
  #SRCCHAIN=$(jq '.chains.src."chain-id"' < path)
  SRCCHAIN=$(grep 'SRC(' path | cut -d'(' -f2 | cut -d')' -f1)
  #DSTCHAIN=$(jq '.chains.dst."chain-id"' < path)
  DSTCHAIN=$(grep 'DST(' path | cut -d'(' -f2 | cut -d')' -f1)
  #CLIENTID=$(jq '.chains.dst."client-id"' < path)
  CLIENTID=$(grep 'ClientID' path | tail -n1 | cut -d':' -f2 | sed 's/ //g')
  TRUSTGET=$(rly q client ${DSTCHAIN} ${CLIENTID} | jq '.client_state.value.trusting_period' | cut -d'"' -f2)
  TRUSTPERIOD=$(( ${TRUSTGET} / 1000000000 ))
  UPDATEPERIOD=$(( ${TRUSTPERIOD} - ${RISKAPPETITE} ))

    #Initiate loop to keep sending client-update within threshold
    while :; do
      GETTIME=$(rly lite header "${SRCCHAIN}" | jq '.' | grep 'time":' | cut -d\" -f4)
      CLIENTTIME=$(date -d "${GETTIME}" +"%s")
      CURRENTTIME=$(date +"%s")
      COMPARE=$(( ${CURRENTTIME} - ${CLIENTTIME} ))
      SLEEPTIME=$(( (${TRUSTPERIOD} - ${COMPARE}) - 99 ))

      #Check how much time do we have until next update
        if [ ${COMPARE} -ge ${TRUSTPERIOD} ]; then
          f_msg error "--- Reached Trust Period or over (${COMPARE} seconds), Client ID: ${CLIENTID} is not active anymore"
          f_msg error "Time on hub for CLIENT-ID: ${CLIENTID}"
          rly q client "${DSTCHAIN}" "${CLIENTID}" | jq '.' | grep 'time":' | cut -d'"' -f4
          exit_on_error
        fi

        if [ ${COMPARE} -ge ${UPDATEPERIOD} ]; then
          unset client_updated

          until [ "${client_updated}" = "ok" ]; do

            f_msg info "--- Limit has been reached ${COMPARE} seconds, updating client (Client: ${CLIENTTIME} Current: ${CURRENTTIME})"
            rly tx raw update-client "${DSTCHAIN}" "${SRCCHAIN}" "${CLIENTID}" > status-update-temp
            cat status-update-temp
            sleep 2
            
            #checking if response contains "update_client" as otherwise it didnt pass through
            grep '"value":"update_client"' status-update-temp >/dev/null

            if [ "$?" -eq "1" ]; then
              f_msg warn "!!! Time wasnt updated on Hub... starting again"
              client_updated="not_ok"
            else
              client_updated="ok"
            fi
          done

          f_msg info "NEW header time: " && rly lite header "${DSTCHAIN}" | jq '.' | grep 'time":' | cut -d\" -f4

      else

          f_msg info "Client time ${CLIENTTIME} is older than Current time ${CURRENTTIME} by ${COMPARE} seconds"
          f_msg info " -- Going to sleep for ${SLEEPTIME} seconds"
          sleep ${SLEEPTIME};

      fi
    done
}

##############################################################################
#
# MAIN
#
##############################################################################


# "$@" will send each position parameter to function as quoted string
case "${1}" in
    update|updat|upda|upd|up|u) PATHNAME="${2}"; f_updateclient "${@}"
        ;;
    --version|-v|version)
        echo "GoZ Phase 1/a/b Update Client v0.1"
        echo "Author: Martin Holovsky (github.com/martinholovsky/)"
        ;;
    *)
        echo "Usage: ${0##*/} update [path-name]"
        echo ""
        exit
        ;;
esac

# clean tempdir
rm -rf "${TEMPDIR}"
exit
