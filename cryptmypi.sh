#!/bin/bash
set -eu
# Creates a configurable kali pi build

# Load functions and environment variables and dependencies
. env.sh;
. functions.sh;
. dependencies.sh;

#Program logic
execute()
{
    #Setup
    check_preconditions;
    install_dependencies;
    check_build_dir_exists;
    create_build_directory_structure;
    
    #Stage 1 - Unpack and modify the image
    _IMAGE_PREPARATION_STARTED=1;
    download_image;
    extract_image;
    copy_extracted_image_to_chroot_dir;
    cleanup_image_prep;
    call_hooks "stage1";
    prepare_image_extras;
    chroot_mkinitramfs "${_CHROOT_ROOT}";
    chroot_umount "${_CHROOT_ROOT}" 
    
    #Stage 2 - Write to physical disk
    fix_block_device_names;
    _WRITE_TO_DISK_STARTED=1;
    setup_filesystem_and_copy_to_disk;
}

# Run Program
main(){
    echo_info "starting $(basename $0) at $(date)";
    execute | tee "${_LOG_FILE}" || true
    echo_info "stopping $(basename $0) at $(date)";
}

# Runs on script exit, tidies up the mounts.
trap "trap_on_exit" EXIT;
trap_on_exit() {
  if (( $_IMAGE_PREPARATION_STARTED > 0 )); then cleanup_image_prep; fi
  if (( $_WRITE_TO_DISK_STARTED > 0 )); then cleanup_write_disk; fi
  echo_error "something went wrong. bye.";
}
main;
