#!/bin/bash
set -e
set -u
chroot_umount || true

# Unmount boot partition
echo_debug "Attempting to unmount ${_BLKDEV}${_PARTITIONPREFIX}1 "
if umount ${_BLKDEV}${_PARTITIONPREFIX}1
then
    echo_debug "- Unmounted ${_BLKDEV}${_PARTITIONPREFIX}1"
else
    echo_error "- Aborting since we failed to unmount ${_BLKDEV}${_PARTITIONPREFIX}1"
    exit 1
fi
echo

# Unmount root partition
echo_debug "Attempting to unmount /mnt/cryptmypi "
if umount /mnt/cryptmypi
then
    echo_debug "- Unmounted /mnt/cryptmypi"
else
    echo_error "- Aborting since we failed to unmount /mnt/cryptmypi"
    exit 1
fi
echo

# Close LUKS
echo_debug "Closing LUKS ${_BLKDEV}${_PARTITIONPREFIX}2"
cryptsetup -v luksClose "/dev/mapper/${_ENCRYPTED_VOLUME_NAME}"

# Clean up
rm -r /mnt/cryptmypi
sync
