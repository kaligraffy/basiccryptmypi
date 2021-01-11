#!/bin/bash
# shellcheck disable=SC1091
set -eu

# Creates a configurable kali pi build

# Load functions, environment variables and dependencies
. env.sh;
. functions.sh;
. options.sh;
. dependencies.sh;

#Program logic
main(){
  echo_info "$(basename $0) started";
  #Setup
  trap 'trap_on_exit 0 0' EXIT;
  check_run_as_root;
  install_dependencies;

  #Check for a build directory
  local rebuild=$(check_build_dir_exists);
  if (( $rebuild >= 1 )); then
    #Stage 1 - Unpack and modify the image
    trap 'trap_on_exit 1 0' EXIT;
    #useful when your build fails during one of the extra setups
    
    if (( $rebuild != 2 )); then
      create_build_directory_structure;
      download_image;
      extract_image;
      mount_image_on_loopback;
      copy_extracted_image_to_chroot_dir;
    fi
    #TODO investigate encryption_setup, extra_setup to stage 2 so any additional setup is applied directly to disk
    chroot_setup;
    chroot_update_apt_setup;
    encryption_setup;
    extra_setup;
    chroot_mkinitramfs_setup;
    chroot_teardown;
  fi
  
  #Stage 2 - Write to physical disk
  trap 'trap_on_exit 1 1' EXIT;
  
  fix_block_device_names;
  check_disk_is_correct;
  copy_to_disk;
  disk_chroot_setup;
  disk_chroot_mkinitramfs_setup;
  extra_extra_setup;
  disk_chroot_teardown;
  exit;
}


# Run program
#TODO Bats testing
#TODO Create an image file functionality rather than writing to sd card
main; #| tee "${_LOG_FILE}";
