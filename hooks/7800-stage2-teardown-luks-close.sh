#!/bin/bash
set -e

# Close LUKS
echo_debug "Closing LUKS ${_BLKDEV}${_PARTITIONPREFIX}2"
cryptsetup -v luksClose "/dev/mapper/${_ENCRYPTED_VOLUME_NAME}"
