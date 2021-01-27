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
  
  if (( $_IMAGE_MODE == 1 )); then 
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
  fi

  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})
  mount_chroot;
  disk_chroot_setup;
}

# Run program
main;
