#!/bin/bash
set -e

# Mount LUKS
echo_debug "Mounting /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"
mkdir /mnt/cryptmypi
if mount /dev/mapper/${_ENCRYPTED_VOLUME_NAME} /mnt/cryptmypi
then
    echo_debug "- Mounted /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"
else
    echo_error "- Abort - failed to mount /dev/mapper/${_ENCRYPTED_VOLUME_NAME} on /mnt/cryptmypi"
    exit 1
fi
echo

# Mount boot partition
echo_debug "Attempting to mount ${_BLKDEV}${__PARTITIONPREFIX}1 to /mnt/cryptmypi/boot ..."
mkdir /mnt/cryptmypi/boot
if mount ${_BLKDEV}${__PARTITIONPREFIX}1 /mnt/cryptmypi/boot
then
    echo_debug "- Mounted ${_BLKDEV}${__PARTITIONPREFIX}1 to /mnt/cryptmypi/boot"
else
    echo_error "- Aborting since we failed to mount ${_BLKDEV}${__PARTITIONPREFIX}1 to /mnt/cryptmypi/boot"
    exit 1
fi
echo
