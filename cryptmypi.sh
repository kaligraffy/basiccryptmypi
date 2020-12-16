#!/bin/bash
set -e

# Get the base url for this script
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SOURCE="$(readlink "$SOURCE")"
[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export _BASEDIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# Load functions and environment variables
. ${_BASEDIR}/functions.sh
. ${_BASEDIR}/env.sh

# EXIT Trap
trap 'trapExit $? $LINENO' EXIT

# Main logic routine
main(){
    stagePreconditions
    cd ${_BUILDDIR}
    echo_info "Starting Cryptmypi at $(date)"
    if [ ! -d ${_BUILDDIR} ]; then
        stage1
    else
        echo_debug "Build directory already exists: ${_BUILDDIR}"
        local CONTINUE
        echo_info "Rebuild? (y/N)"
        read _CONTINUE
        CONTINUE=$(echo "${CONTINUE}" | sed -e 's/\(.*\)/\L\1/')
        
        if [ "${CONTINUE}" = 'y' ] || [ "${CONTINUE}" = 'Y' ]; then
            echo_warn "Cleaning old build."
            rm -Rf ${_BUILDDIR}
        fi
        stage1
    fi
    
    myhooks 0000-experimental-boot-hash.sh
    #myhooks 0000-experimental-initramfs-iodine.sh
    myhooks 0000-experimental-initramfs-wifi.sh
    #myhooks 0000-experimental-sys-iodine.sh
    myhooks 0000-optional-initramfs-luksnuke.sh
    myhooks 0000-optional-sys-cpugovernor-ondemand.sh
    myhooks 0000-optional-sys-dns.sh
    #myhooks 0000-optional-sys-docker.sh
    myhooks 0000-optional-sys-rootpassword.sh
    #myhooks 0000-optional-sys-vpnclient.sh
    #myhooks 0000-optional-sys-wifi.sh
    
    stage2
    exit 0
}

main | tee ${_BUILDDIR}/build.log
