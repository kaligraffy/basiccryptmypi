#!/bin/bash
set -e

echo_debug "Attempting to open LUKS ${_BLKDEV}${_PARTITIONPREFIX}2 "
echo "${_LUKSPASSWD}" | cryptsetup -v luksOpen ${_BLKDEV}${_PARTITIONPREFIX}2 ${_ENCRYPTED_VOLUME_NAME}
echo_debug "- LUKS open"
