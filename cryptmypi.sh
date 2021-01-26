#!/bin/bash
# shellcheck disable=SC1091
set -eu

# Creates a configurable kali pi build

# Load functions, environment variables and dependencies
. functions.sh;
. env.sh;
. options.sh;
. dependencies.sh;

#Program logic
main(){
  echo_info "$(basename $0) started";
  #Setup
  trap 'trap_on_exit 0' EXIT;
  check_run_as_root;
  install_dependencies;
  options_check;
  download_image;
  extract_image;
  
  #Check for a build directory
  local delete_build=$(check_build_dir_exists);
  if (( $delete_build == 1 )); then
    create_build_directory
  fi
  
  # Write to physical disk or image and modify it
  trap 'trap_on_exit 1' EXIT;
  if (( $_IMAGE_MODE == 1 )); then 
    partition_image_file;
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
    partition_disk;
  fi
  format_filesystem;
  mount_chroot;
  copy_image_on_loopback_to_disk;
  disk_chroot_setup;
  arm_setup;
  locale_setup
  disk_chroot_update_apt_setup;
  filesystem_setup;
  encryption_setup;
  optional_setup;
  disk_chroot_mkinitramfs_setup;
  
  if (( $_IMAGE_MODE == 1 )); then
    echo_info "To burn your disk run: dd if=${_IMAGE_FILE} of=${_OUTPUT_BLOCK_DEVICE} bs=512 status=progress && sync";
  fi
  exit 0;
}

# Run program
#TODO Bats testing
main;
