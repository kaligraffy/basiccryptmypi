#!/bin/bash
myhooks(){
    local _HOOK=''
    if [ ! -z "${1}" ]; then
        _HOOKOP="${1}"
        for _HOOK in ${_BASEDIR}/hooks/????-${_HOOKOP}*.hook
        do
            if [ -e ${_HOOK} ]; then
                echo_info "- Calling $(basename ${_HOOK}) ..."
                $_SIMULATE && {
                    echo_debug "SKIPPING: Simulation mode active: Hook will not be executed."
                } || source ${_HOOK}
                echo_debug "- $(basename ${_HOOK}) completed"
            fi
        done
    else
        echo_error "Hook operations not specified!"
        exit 1
    fi
}
