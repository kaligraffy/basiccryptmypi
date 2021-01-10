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
  echo_info_time "$(basename $0) started";
  #Setup
  check_run_as_root;
  install_dependencies;
  fix_block_device_names;

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
      mount_loopback_image;
      copy_extracted_image_to_chroot_dir;
    fi
    #TODO investigate move locale_setup, encryption_setup, extra_setup to stage 2 so any additional setup is applied directly to disk
    chroot_setup;
    locale_setup;
    encryption_setup;
    extra_setup;
    chroot_mkinitramfs_setup;
    chroot_teardown;
  fi
  
  #Stage 2 - Write to physical disk
  trap 'trap_on_exit 1 1' EXIT;
  check_disk_is_correct;
  copy_to_disk;
  disk_chroot_setup;
  disk_chroot_mkinitramfs;
  extra_extra_setup;
  disk_chroot_teardown;
  exit;
}


# Run program
#TODO Investigate logging missing from build log
#TODO Bats testing
main | tee "${_LOG_FILE}";
