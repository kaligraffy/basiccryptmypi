#!/bin/bash
set -e
set -u

# Attempt to copy files from build to mounted device
echo_debug "Syncing build to disk"
echo_info "Starting copy of build to ${_CHROOT_ROOT} at $(date)"
rsync \
  --hard-links \
  --archive \
  --verbose \
  --partial \
  --progress \
  --quiet \
  --info=progress2 "${_BUILDDIR}/mount/"* "${_CHROOT_ROOT}"
  
# Sync file system
echo_debug "Syncing the filesystems ."
sync
