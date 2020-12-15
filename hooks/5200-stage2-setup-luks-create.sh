#!/bin/bash
set -e

# Create LUKS
echo_debug "Attempting to create LUKS ${_BLKDEV}${__PARTITIONPREFIX}2 ..."
if [ ! -z "${_LUKSPASSWD}" ]; then
    echo "${_LUKSPASSWD}" | cryptsetup -v --cipher ${_LUKSCIPHER} ${_LUKSEXTRA} luksFormat ${_BLKDEV}${__PARTITIONPREFIX}2 
    if [ $? -eq 0 ]; then
        echo_debug "- LUKS created."
    else
        echo_error "- Aborting since we failed to create LUKS on ${_BLKDEV}${__PARTITIONPREFIX}2"
        exit 1
    fi
fi

