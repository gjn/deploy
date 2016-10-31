#!/bin/bash
set -e
set -o pipefail
USER=$(logname) # get user behind sudo su - 

# if trigger script is called by deploy.sh, log parents pid in syslog
# PARENT_COMMAND: you will get empty_string if it was invoked by user and name_of_calling_script if it was invoked by other script.
PARENT_COMMAND=$(ps $PPID | tail -n 1 | awk "{print \$6}")
SYSLOGPID=$$
if [[ ${PARENT_COMMAND} == *deploy.sh ]]; then
    SYSLOGPID="${PPID}..$$"
fi
comment="manual db deploy"
if [ "${message}" ]; then
    comment="${message}"
fi

INFO="${0##*/} - ${USER} - ${comment} - [${SYSLOGPID}] - INFO"
ERROR="${0##*/} - ${USER} - ${comment} - [${SYSLOGPID}] - ERROR"

COMMAND="${0##*/} $* (pid: $$)"
locktext="${0##*/} - [$$] locked by ${USER} ${COMMAND} @ $(date +"%F %T")"
lockfile="/tmp/db_deploy.lock"

# coloured output
red='\e[0;31m'
NC='\e[0m' # No Color

# space delimited list of valid deploy targets, the target will be used as database suffix
targets="dev int prod demo tile"
targets_toposhop="dev int"

#######################################
# Logging
# Globals:
#   INFO
# Arguments:
#   pipe data
# Returns:
#   prefixed stdout to screen and syslog
#######################################
log () {
    exec 40> >(exec logger -t "${INFO}")
    local data
    while read data
    do
        echo "INFO: $1${data}"
        echo "$1${data}" >&40
    done
    exec 40>&- 
}

#######################################
# Error Logging
# Globals:
#   ERROR
# Arguments:
#   pipe data
# Returns:
#   prefixed stderr to screen and syslog
#######################################
err() {
    exec 40> >(exec logger -t "${ERROR}" )
    local data
    while read data
    do
        echo -e "${red}ERROR: $1${data}${NC}" >&2
        echo "$1${data}" >&40
    done    
    exec 40>&- 
}

#######################################
# Ceiling,
# the smallest integer value greater than or equal to $1/$2
# Globals:
#   None
# Arguments:
#   $1 integer -> dividend
#   $2 integer -> divisor
# Returns:
#   integer
#######################################
Ceiling () {
  python -c "from math import ceil; print int(ceil(float($1)/float($2)))"
}

#######################################
# pretty print milliseconds
# Globals:
#   None
# Arguments:
#   milliseconds
# Returns:
#   formatted string
#######################################
format_milliseconds() {
    seconds=$(($1/1000))
    printf '%dh:%dm:%ds.%d - %d milliseconds\n' $((${seconds}/3600)) $((${seconds}%3600/60)) $((${seconds}%60)) $(($1 % 1000)) $1
}

exec 5>&1
exec 6>&2
# stdout to log function
exec 1> >(log)
# stdout to err function
exec 2> >(err)

# check environment variables
check_env() {
    # check for deploy.cfg, if exists read variables from file
    MY_DIR=$(dirname $(readlink -f $0))
    if [[ -f "${MY_DIR}/deploy.cfg" ]]; then 
        source "${MY_DIR}/deploy.cfg"
    fi

    failed=false
    # DB superuser, set and not empty
    if [[ -z "${PGUSER}" ]]; then
        echo 'export env variable containing DB Superuser name: $ export PGUSER=xxx' >&2
        failed=true
    fi
    # SPHINX DEV, set and not empty
    if [[ -z "${SPHINX_DEV}" ]]; then
        echo 'export env variable containing SPHINX DEV ip address (space delimiter): $ export SPHINX_DEV="ipaddress1 ipaddress2"' >&2
        failed=true
    fi
    # SPHINX INT, set and not empty
    if [[ -z "${SPHINX_INT}" ]]; then
        echo 'export env variable containing SPHINX INT ip address (space delimiter): $ export SPHINX_INT="ipaddress1 ipaddress2"' >&2
        failed=true
    fi
    # SPHINX PROD, set and not empty
    if [[ -z "${SPHINX_PROD}" ]]; then
        echo 'export env variable containing SPHINX PROD ip address (space delimiter): $ export SPHINX_PROD="ipaddress1 ipaddress2"' >&2
        failed=true
    fi   
    # SPHINX DEMO, has to be set, can be empty
    if [[ -z "${SPHINX_DEMO}" ]]; then
        echo 'export env variable containing SPHINX DEMO ip address (space delimiter): $ export SPHINX_DEMO="ipaddress1 ipaddress2"' >&2
        failed=true
    fi
    # PUBLISHED SLAVES set to default value if empty
    # pipe delimited list of published slaves ips p.e. "ip1|ip2|ip3"
    # the deploy script will wait for these slaves to by in-sync before starting the dml (sphinx) trigger
    # normally these list should contain the ip's behind pg-sandbox.bgdi.ch and pg.bgdi.ch, default value is '.*' = all slaves
    if [[ -z "${PUBLISHED_SLAVES}" ]];then
        PUBLISHED_SLAVES='.*'
    fi
    if [[ "${failed}" = true ]];then
        echo "you can set the variables in ${MY_DIR}/deploy.cfg" 
        exit 1
    fi
}

# check for env variables
check_env

# force geodata
if [[ $(whoami) != "geodata" ]]; 
then 
    echo "This script must be run as geodata!" >&2
    exit 1
fi
