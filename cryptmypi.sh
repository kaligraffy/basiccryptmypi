#!/bin/bash
set -e

# Get the base path for this script
export _BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Load functions and environment variables
. ${_BASEDIR}/env.sh
. ${_BASEDIR}/functions.sh
. ${_BASEDIR}/dependencies.sh

# EXIT Trap
trap 'trapExit $? $LINENO' EXIT

#Program Logic
execute()
{
    echo_info "Starting Cryptmypi at $(date)"
    stagePreconditions    
    if [ ! -d ${_BUILDDIR} ]; then
        stage1
    else
        echo_debug "Build directory already exists: ${_BUILDDIR}"
        local CONTINUE
        read -p "Rebuild? (y/N)" CONTINUE
        if [ "${CONTINUE}" = 'y' ] || [ "${CONTINUE}" = 'Y' ]; then
            echo_warn "Cleaning old build"
            rm -Rf ${_BUILDDIR}
        fi
        stage1
    fi
    export _CHROOT_ROOT=/mnt/cryptmypi #NASTY, fix later.
    stage2
    exit 0
}

# Run Program
main(){
    execute | tee ${_BASEDIR}/build.log
}
main
