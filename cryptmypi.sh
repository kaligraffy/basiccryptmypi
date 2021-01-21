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
  dependency_check;
  #image extract
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
    format_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
    format_disk;
  fi
  copy_image_on_loopback_to_disk;
  arm_setup;
  disk_chroot_setup;
  disk_chroot_update_apt_setup;
  filesystem_setup;
  encryption_setup;
  optional_setup;
  disk_chroot_mkinitramfs_setup;
  exit 0;
}

# Run program
#TODO Bats testing
main;
