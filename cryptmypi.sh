#!/bin/bash
set -eu
# Creates a configurable kali pi build

# Load functions and environment variables and dependencies
. env.sh;
. functions.sh;
. dependencies.sh;
 
  trap 'trap_on_exit' EXIT;
  trap 'trap_on_error $LINENO' ERR;
  trap 'trap_on_interrupt' SIGINT;
#Program logic
execute()
{
  echo_info "starting $(basename $0) at $(date)";
  
  #Setup
  check_preconditions;
  install_dependencies;
  
  #Check for a build directory
  local rebuild=$(check_build_dir_exists);
  if (( $rebuild == 1 )); then
    rm -rf ${_BUILD_DIR} || true ;
    #Stage 1 - Unpack and modify the image
    create_build_directory_structure;
    export _IMAGE_PREPARATION_STARTED=1;
    download_image;
    extract_image;
    copy_extracted_image_to_chroot_dir;
    cleanup_image_prep;
    call_hooks "stage1";
    prepare_image_extras;
    chroot_mkinitramfs "${_CHROOT_ROOT}";
    chroot_umount "${_CHROOT_ROOT}" 
  fi
  
  #Stage 2 - Write to physical disk
  fix_block_device_names;
  export _WRITE_TO_DISK_STARTED=1;
  setup_filesystem_and_copy_to_disk;
}

# Run Program
main(){
  execute | tee "${_LOG_FILE}" || true
  exit;
}
main;
