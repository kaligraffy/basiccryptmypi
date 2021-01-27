#!/bin/bash
# shellcheck disable=SC1091
set -eu

# Creates a configurable kali pi build

# Load functions, environment variables and dependencies
. functions.sh;
. env.sh;
. options.sh;

print_usage(){
  local usage=$(cat << 'HERE' 
Usage: ./cryptmypi.sh ARG1
ARG1 can be:
-b or build - standard build
-nx or build_no_extract - build without preparing the filesystem
-m or mount_only - only mount an image or disk
-u or unmount - unmount
-h or help - prints this help message
HERE
)
  echo -e "$usage";
}

unmount(){
  trap 'trap_on_exit 0' EXIT;
  check_run_as_root;
  cleanup;
}

mount_only(){
  trap 'trap_on_exit 0' EXIT;
  check_run_as_root;
  
  if (( $_IMAGE_MODE == 1 )); then 
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
  fi

  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})
  mount_chroot;
  chroot_setup;
}

build_no_extract(){
  trap 'trap_on_exit 0' EXIT;
  check_run_as_root;
  install_dependencies;
  set_defaults;
  echo_info "Running with settings:" 
  set | grep '^_'
  options_check;
  
  # Write to physical disk or image and modify it
  trap 'trap_on_exit 1' EXIT;
  if (( $_IMAGE_MODE == 1 )); then 
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
  fi 
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})
  mount_chroot;
  chroot_setup;
  arm_setup;
  chroot_install_eatmydata;
  locale_setup
  chroot_apt_setup;
  filesystem_setup;
  encryption_setup;
  optional_setup;
  chroot_mkinitramfs_setup;
  
  if (( $_IMAGE_MODE == 1 )); then
    echo_info "To burn your disk run: dd if=${_IMAGE_FILE} of=${_OUTPUT_BLOCK_DEVICE} bs=512 status=progress && sync";
  fi
  exit 0;
}

#Program logic
build(){
  trap 'trap_on_exit 0' EXIT;
  check_run_as_root;
  install_dependencies;
  set_defaults;
  echo_info "Running with settings:" 
  set | grep '^_'
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
  chroot_setup;
  arm_setup;
  chroot_install_eatmydata;
  locale_setup
  chroot_apt_setup;
  filesystem_setup;
  encryption_setup;
  optional_setup;
  chroot_mkinitramfs_setup;
  
  if (( $_IMAGE_MODE == 1 )); then
    echo_info "To burn your disk run: dd if=${_IMAGE_FILE} of=${_OUTPUT_BLOCK_DEVICE} bs=512 status=progress && sync";
  fi
}

main(){
  echo_info "$(basename $0) started";
   
  case $1 in
    build|-b)
      build;
      ;;
    build_no_extract|-nx)
      build_no_extract;
      ;;
    mount_only|-m)
      mount_only;
      ;;
    unmount|-u)
      unmount;
      ;;
    help|-h)
      print_usage;
      ;;
    *)
      print_usage;
      ;;
  esac
  exit 0;
}

# Run program
#TODO Bats testing
main "$1";
