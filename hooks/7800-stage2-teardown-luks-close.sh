#!/bin/bash
set -e

# Close LUKS
echo_debug "CLosing LUKS ${_BLKDEV}${__PARTITIONPREFIX}2"
if cryptsetup -v luksClose /dev/mapper/${_ENCRYPTED_VOLUME_NAME}
then
    echo_debug "- LUKS closed."
else
    echo_error "- Abort - failed to close LUKS /dev/mapper/${_ENCRYPTED_VOLUME_NAME}"
    exit 1
fi