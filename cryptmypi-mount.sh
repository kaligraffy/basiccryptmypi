#!/bin/bash
# shellcheck disable=SC1091
set -eu

# Mounts image file

# Load functions, environment variables and dependencies
. functions.sh;
. env.sh;
. options.sh;
. dependencies.sh;

#Program logic
main(){
  echo_info "$(basename $0) started";
  loopback_image_file;
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})
  mount_chroot;
  disk_chroot_setup;
}

# Run program
main;
