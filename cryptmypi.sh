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
  fix_block_device_names;
  create_build_directory_structure;

  #Check for a build directory
  local extract=$(check_build_dir_exists);
  if (( $extract >= 1 )); then
    #Stage 1 - Unpack image
    rm -rf "${_BUILD_DIR}" || true ;
    create_build_directory_structure
    download_image;
    extract_image;
  fi
  
  #Stage 2 - Write to physical disk or image and modify it
  trap 'trap_on_exit 1' EXIT;
  if (( $_IMAGE_MODE == 1 )); then 
    copy_to_image_file;
  else
    check_disk_is_correct;
    copy_to_disk;
  fi
  mount_image_on_loopback;
  copy_extracted_image_to_chroot_dir;
  disk_chroot_setup;
  disk_chroot_update_apt_setup;
  encryption_setup;
  extra_setup;
  disk_chroot_mkinitramfs_setup;
  exit 0;
}

# Run program
#TODO Bats testing
main;
