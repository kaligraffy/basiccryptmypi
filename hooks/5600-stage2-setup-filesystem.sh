#!/bin/bash
set -e
set -u

# Attempt to copy files from build to mounted device
echo_debug "Attempting to cp ${_CHROOT_ROOT}/ to /mnt/cryptmypi/ ..."
cp -a "${_CHROOT_ROOT}/"* /mnt/cryptmypi/

# Sync file system
echo_debug "Syncing the filesystems ...."
sync
