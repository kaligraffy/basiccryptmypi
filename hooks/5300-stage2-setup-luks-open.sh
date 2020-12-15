#!/bin/bash
set -e

echo_debug "Attempting to open LUKS ${_BLKDEV}${__PARTITIONPREFIX}2 ..."
if [ ! -z "${_LUKSPASSWD}" ]; then
    echo "${_LUKSPASSWD}" | cryptsetup -v luksOpen ${_BLKDEV}${__PARTITIONPREFIX}2 ${_ENCRYPTED_VOLUME_NAME} 
    if [ $? -eq 0 ]; then
        echo_debug "- LUKS open"
    else
        echo_error "- Aborting since we failed to create LUKS on ${_BLKDEV}${__PARTITIONPREFIX}2"
        exit 1
    fi
fi
