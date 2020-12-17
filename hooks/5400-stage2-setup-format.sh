#!/bin/bash
set -e

FS=$_FILESYSTEM_TYPE

# Format
echo_debug "Formatting /dev/mapper/${_ENCRYPTED_VOLUME_NAME}"
mkfs.$FS /dev/mapper/${_ENCRYPTED_VOLUME_NAME}
echo_debug "- Formatted"

# Format boot partition
echo_debug "Formatting Boot Partition"
mkfs.vfat ${_BLKDEV}${_PARTITIONPREFIX}1
