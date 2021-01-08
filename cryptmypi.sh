#!/bin/bash
# shellcheck disable=SC1091
set -eu

# Creates a configurable kali pi build

# Load functions, environment variables and dependencies
. env.sh;
. functions.sh;
. options.sh;
. dependencies.sh;

trap 'trap_on_exit' EXIT;
trap 'trap_on_error $LINENO' ERR;
trap 'trap_on_interrupt' SIGINT;

#Program logic
main(){
  echo_info_time "$(basename $0)";
  #Setup
  check_run_as_root;
  install_dependencies;
  fix_block_device_names;

  #Check for a build directory
  local rebuild=$(check_build_dir_exists);
  if (( $rebuild >= 1 )); then
    #Stage 1 - Unpack and modify the image
    export _IMAGE_PREPARATION_STARTED=1;
    #useful when your build fails during one of the extra setups
    if (( $rebuild != 2 )); then
      create_build_directory_structure;
      download_image;
      extract_image;
      mount_loopback_image;
      copy_extracted_image_to_chroot_dir;
    fi
    chroot_setup;
    locale_setup;
    encryption_setup;
    extra_setup;
    chroot_mkinitramfs_setup;
    chroot_teardown;
  fi
  
  #Stage 2 - Write to physical disk
  export _WRITE_TO_DISK_STARTED=1;
  check_disk_is_correct;
  copy_to_disk;
  disk_chroot_setup;
  disk_chroot_mkinitramfs;
  extra_extra_setup;
  disk_chroot_teardown;
  exit;
}
# Run program
main | tee "${_LOG_FILE}" || true;
