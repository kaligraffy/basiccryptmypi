#!/bin/bash
set -e

# Attempt to copy files from build to mounted device
echo_debug "Attempting to cp ${_BUILDDIR}/root/ to /mnt/cryptmypi/ ..."
cp -a "${_BUILDDIR}/root/"* /mnt/cryptmypi/
echo

# Sync file system
echo_debug "Syncing the filesystems ...."
sync
