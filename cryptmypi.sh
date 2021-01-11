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
  #TODO fix_block_device_names must run before stage1 due to the chroot_mkinitramfs_setup script
  #in stage1, it would be nice to be able to run stage1 without having to specify a 'real' device name'.
  # atm, it'll exit if the device is invalid
  fix_block_device_names;

  #Check for a build directory
  local rebuild=$(check_build_dir_exists);
  if (( $rebuild >= 1 )); then
    #Stage 1 - Unpack and modify the image
    trap 'trap_on_exit 1 0' EXIT;

    #useful when your build fails during one of the extra setups,selecting 'p' in the check skips the extract  
    if (( $rebuild != 2 )); then
      create_build_directory_structure;
      download_image;
      extract_image;
      mount_image_on_loopback;
      copy_extracted_image_to_chroot_dir;
    fi
    chroot_setup;
    chroot_update_apt_setup;
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
  disk_chroot_mkinitramfs_setup;
  extra_extra_setup;
  disk_chroot_teardown;
  exit;
}

# Run program
#TODO Bats testing
#TODO Create an image file functionality rather than writing to sd card
#TODO investigate moving encryption_setup, extra_setup to stage 2 so any additional setup is applied directly to disk
#TODO replace stage 1, stage 2 logic, so there is only one mkinitramfs call to deduplicate calls to mkinitramfs and copying data out of the extracted image
#in this re-envisioned script, stage 1 would create an image file on disk, format it and copy files to it.
#all setup would occur inside a chroot of this image file, including the call to mkinitramfs
#the final product of stage 1 will be an image file containing all extra setup and extra extra setup
#stage 2 no setup or mkinitramfs will occur. stage 2 will simply dd the image file to the selected disk.
main;
