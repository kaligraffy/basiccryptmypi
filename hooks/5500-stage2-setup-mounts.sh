#!/bin/bash
set -e
set -u

# Mount LUKS
echo_debug "Mounting /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"
mkdir /mnt/cryptmypi
mount /dev/mapper/${_ENCRYPTED_VOLUME_NAME} /mnt/cryptmypi && echo_debug "- Mounted /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"

# Mount boot partition
echo_debug "Attempting to mount ${_BLKDEV}${_PARTITIONPREFIX}1 to /mnt/cryptmypi/boot "
mkdir /mnt/cryptmypi/boot
if mount ${_BLKDEV}${_PARTITIONPREFIX}1 /mnt/cryptmypi/boot && echo_debug "- Mounted ${_BLKDEV}${_PARTITIONPREFIX}1 to /mnt/cryptmypi/boot"

