#!/bin/bash
myhooks(){
    local _HOOK=''
    if [ ! -z "${1}" ]; then
        _HOOKOP="${1}"
        for _HOOK in ${_BASEDIR}/hooks/????-${_HOOKOP}*.sh
        do
            if [ -e ${_HOOK} ]; then
                echo_info "- Calling $(basename ${_HOOK}) ..."
                source ${_HOOK}
                echo_debug "- $(basename ${_HOOK}) completed"
            fi
        done
    else
        echo_error "Hook operations not specified!"
        exit 1
    fi
}
