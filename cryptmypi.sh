#!/bin/bash
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
  if (( $rebuild == 1 )); then
    #Stage 1 - Unpack and modify the image
    create_build_directory_structure;
    export _IMAGE_PREPARATION_STARTED=1;
    download_image;
    extract_image;
    mount_loopback_image;
    copy_extracted_image_to_chroot_dir;
    chroot_setup;
    locale_setup;
    encryption_setup;
    extra_setup;
    chroot_teardown;
  fi
  
  #Stage 2 - Write to physical disk
  export _WRITE_TO_DISK_STARTED=1;
  check_disk_is_correct;
  copy_to_disk;
  chroot_mount "${_DISK_CHROOT_ROOT}"
  chroot_mkinitramfs "${_DISK_CHROOT_ROOT}"
  extra_extra_setup;
  exit;
}
# Run program
main | tee "${_LOG_FILE}" || true;
