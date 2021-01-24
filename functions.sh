#!/bin/bash
# shellcheck disable=SC2128
# shellcheck disable=SC2034
# shellcheck disable=SC2145
# shellcheck disable=SC2086
# shellcheck disable=SC2068
set -eu

#Global variables
declare -xr _BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";
declare -xr _BUILD_DIR=${_BASE_DIR}/build
declare -xr _FILE_DIR=${_BASE_DIR}/files
declare -xr _EXTRACTED_IMAGE="${_FILE_DIR}/extracted.img"
declare -xr _CHROOT_DIR=${_BUILD_DIR}/disk
declare -xr _ENCRYPTED_VOLUME_PATH="/dev/mapper/crypt-2"
declare -xr _COLOR_ERROR='\033[0;31m' #red
declare -xr _COLOR_WARN='\033[1;33m' #orange
declare -xr _COLOR_INFO='\033[0;35m' #purple
declare -xr _COLOR_DEBUG='\033[0;37m' #grey
declare -xr _COLOR_NORMAL='\033[0m' # No Color
declare -xr _LOG_FILE="${_BASE_DIR}/build-$(date '+%Y-%m-%d-%H:%M:%S').log"
declare -xr _IMAGE_FILE="${_BUILD_DIR}/image.img"
declare -xr _IMAGE_FILE_SIZE="11G"; #size of image file, set it near your sd card if you have the space so you don't have to resize your disk
declare _BLOCK_DEVICE_BOOT=""
declare _BLOCK_DEVICE_ROOT="" 
# Runs on script exit, tidies up the mounts.
trap_on_exit(){
  echo_info "Running trap on exit";
  if (( $1 == 1 )); then 
    cleanup_write_disk; 
  fi
  echo_info "$(basename $0) finished";
}

# Cleanup stage 2
cleanup_write_disk(){
  echo_info "$FUNCNAME";
  tidy_umount "${_BUILD_DIR}/mount" || true
  tidy_umount "${_BUILD_DIR}/boot" || true

  disk_chroot_teardown || true 
  tidy_umount "${_BLOCK_DEVICE_BOOT}" || true 
  tidy_umount "${_BLOCK_DEVICE_ROOT}" || true 
  tidy_umount "${_CHROOT_DIR}" || true 
  if [[ -b ${_ENCRYPTED_VOLUME_PATH} ]]; then
    cryptsetup -v luksClose "$(basename ${_ENCRYPTED_VOLUME_PATH})" || true
    cryptsetup -v remove $(basename ${_ENCRYPTED_VOLUME_PATH}) || true
  fi
  cleanup_loop_devices || true 
    
  if (( $_IMAGE_MODE == 1 )); then
    echo_info "To burn your disk run: dd if=${_IMAGE_FILE} of=${_OUTPUT_BLOCK_DEVICE} bs=512 status=progress && sync";
  fi
}

#auxiliary method for detaching loop_device in cleanup method 
cleanup_loop_devices(){
  echo_info "$FUNCNAME";
  loop_devices="$(losetup -a | cut -d':' -f 1 | tr '\n' ' ')";
  if [[ $(check_variable_is_set "$loop_devices") ]]; then
    for loop_device in $loop_devices; do
      if losetup -l "${loop_device}p1" ; then echo_debug "loop device, detach it"; losetup -d "${loop_device}p1"; fi
      if losetup -l "${loop_device}p2" ; then echo_debug "loop device, detach it"; losetup -d "${loop_device}p2"; fi
      if losetup -l "${loop_device}" ; then echo_debug "loop device, detach it"; losetup -d "${loop_device}"; fi
    done
  fi
}

#check if theres a build directory already
check_build_dir_exists(){
  #no echo as interferes with return echos
  if [ -d ${_BUILD_DIR} ]; then
    
    if (( ${_NO_PROMPTS} == 1 )); then  
      echo '1';
      return;
    fi
    
    local continue;
    read -p "Build directory already exists: ${_BUILD_DIR}. Delete? (y/N)  " continue;
    if [ "${continue}" = 'y' ] || [ "${continue}" = 'Y' ]; then
      echo '1';
    else
      echo '0'; 
    fi
  else
    echo '1';
  fi
}

#checks if script was run with root
check_run_as_root(){
  echo_info "$FUNCNAME";
  if (( $EUID != 0 )); then
    echo_error "This script must be run as root/sudo";
    exit 1;
  fi
}

#Fix for using mmcblk0pX devices, adds a p used later on
fix_block_device_names(){
  # check device exists/folder exists
  echo_info "$FUNCNAME";
  
  if ! check_variable_is_set "${_OUTPUT_BLOCK_DEVICE}"; then
    exit 1;
  fi

  local prefix=""
  #if the device contains mmcblk, prefix is set so the device name is picked up correctly
  if [[ "${_OUTPUT_BLOCK_DEVICE}" == *'mmcblk'* ]]; then
    prefix='p'
  fi
  #Set the proper name of the output block device's partitions
  #e.g /dev/sda1 /dev/sda2 etc.
  declare -xr _BLOCK_DEVICE_BOOT="${_OUTPUT_BLOCK_DEVICE}${prefix}1"
  declare -xr _BLOCK_DEVICE_ROOT="${_OUTPUT_BLOCK_DEVICE}${prefix}2"
}


create_build_directory(){
  echo_info "$FUNCNAME";
  rm -rf "${_BUILD_DIR}" || true ;
  mkdir "${_BUILD_DIR}" || true; 
  sync;
}

#extracts the image so it can be mounted
extract_image() {
  echo_info "$FUNCNAME";

  local image_name="$(basename ${_IMAGE_URL})";
  local image_path="${_FILE_DIR}/${image_name}";
  local extracted_image="${_EXTRACTED_IMAGE}";

  #If no prompts is set and extracted image exists then continue to extract
  
  if [[ -e "${extracted_image}" ]] && (( ${_NO_PROMPTS} == 1 )); then
    return 0;
  fi  
    
  if [[ -e "${extracted_image}" ]] ; then
    local continue="";
    read -p "${extracted_image} found, re-extract? (y/N)  " continue;
    if [ "${continue}" != 'y' ] && [ "${continue}" != 'Y' ]; then
       return 0;
    fi
  fi

  echo_info "starting extract";
  #If theres a problem extracting, delete the partially extracted file and exit
  trap 'rm $(echo $extracted_image); exit 1' ERR SIGINT;
  case ${image_path} in
    *.xz)
        echo_info "extracting with xz";
        pv ${image_path} | xz --decompress --stdout > "$extracted_image";
        ;;
    *.zip)
        echo_info "extracting with unzip";
        unzip -p $image_path > "$extracted_image";
        ;;
    *)
        echo_error "unknown extension type on image: $image_path";
        exit 1;
        ;;
  esac
  trap - ERR SIGINT;
  echo_info "finished extract";
}

#mounts the extracted image via losetup
copy_image_on_loopback_to_disk(){
  echo_info "$FUNCNAME";
  local extracted_image="${_EXTRACTED_IMAGE}";
  local loop_device=$(losetup -P -f --read-only --show "$extracted_image");
  partprobe ${loop_device};
  check_directory_and_mount "${loop_device}p2" "${_BUILD_DIR}/mount";
  check_directory_and_mount "${loop_device}p1" "${_BUILD_DIR}/boot";

  rsync_local "${_BUILD_DIR}/boot" "${_CHROOT_DIR}/"
  rsync_local "${_BUILD_DIR}/mount/"* "${_CHROOT_DIR}"
}

#prompts to check disk is correct before writing out to disk, 
#if no prompts is set, it skips the check
check_disk_is_correct(){
  if [ ! -b "${_OUTPUT_BLOCK_DEVICE}" ]; then
    echo_error "${_OUTPUT_BLOCK_DEVICE} is not a block device" 
    exit 0
  fi
  
  echo_info "$FUNCNAME";
  if [ "${_NO_PROMPTS}" -eq 0 ]; then
    local continue
    echo_info "$(lsblk)";
    echo_warn "CHECK THE DISK IS CORRECT";
    read -p "Type 'YES' if the selected device is correct:  ${_OUTPUT_BLOCK_DEVICE}  " continue
    if [ "${continue}" != 'YES' ] ; then
        exit 0
    fi
  fi
}

#Download an image file to the file directory
download_image(){
  echo_info "$FUNCNAME";

  local image_name=$(basename ${_IMAGE_URL})
  local image_out_file=${_FILE_DIR}/${image_name}
  wget -nc "${_IMAGE_URL}" -O "${image_out_file}" || true
  if [ -z ${_IMAGE_SHA256} ]; then
    echo_info "skip checksumming image";
    return 0
  fi
  echo_info "checksumming image";
  echo ${_IMAGE_SHA256}  $image_out_file | sha256sum --check --status
  if [ $? != '0' ]; then
    echo_error "invalid checksum";
    exit;
  fi
  echo_info "valid checksum";
}

#sets up encryption settings in chroot
encryption_setup(){
  echo_info "$FUNCNAME";
  
  chroot_package_install cryptsetup busybox

  # Creating symbolic link to e2fsck
  chroot ${_CHROOT_DIR} /bin/bash -c "test -L /sbin/fsck.luks || ln -s /sbin/e2fsck /sbin/fsck.luks"

  # Indicate kernel to use initramfs - facilitates loading drivers
  atomic_append 'initramfs initramfs.gz followkernel' "${_CHROOT_DIR}/boot/config.txt";
  
  # Update /boot/cmdline.txt to boot crypt
  sed -i "s|root=/dev/mmcblk0p2|root=${_ENCRYPTED_VOLUME_PATH} cryptdevice=/dev/mmcblk0p2:$(basename ${_ENCRYPTED_VOLUME_PATH})|g" ${_CHROOT_DIR}/boot/cmdline.txt
  sed -i "s|rootfstype=ext3|rootfstype=${fs_type}|g" ${_CHROOT_DIR}/boot/cmdline.txt
  

  # Enable cryptsetup when building initramfs
  atomic_append 'CRYPTSETUP=y' "${_CHROOT_DIR}/etc/cryptsetup-initramfs/conf-hook"  
  
  # Update /etc/fstab
  sed -i "s|/dev/mmcblk0p2|${_ENCRYPTED_VOLUME_PATH}|g" ${_CHROOT_DIR}/etc/fstab
  sed -i "s#ext3#${fs_type}#g" ${_CHROOT_DIR}/etc/fstab

  # Update /etc/crypttab
  echo "# <target name> <source device>         <key file>      <options>" > "${_CHROOT_DIR}/etc/crypttab"
  atomic_append "$(basename ${_ENCRYPTED_VOLUME_PATH})    /dev/mmcblk0p2    none    luks" "${_CHROOT_DIR}/etc/crypttab"

  # Create a hook to include our crypttab in the initramfs
  cp -p "${_FILE_DIR}/initramfs-scripts/zz-cryptsetup" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/zz-cryptsetup";
  
  # Adding dm_mod to initramfs modules
  atomic_append 'dm_crypt' "${_CHROOT_DIR}/etc/initramfs-tools/modules";
  
  # Disable autoresize
  chroot_execute systemctl disable rpi-resizerootfs.service
  chroot_execute systemctl disable rpiwiggle.service
}

# Encrypt & Write SD
partition_disk(){  
  echo_info "$FUNCNAME";
  parted_disk_setup ${_OUTPUT_BLOCK_DEVICE} 
}

#makes an image file instead of copying to a disk
partition_image_file(){
  echo_info "$FUNCNAME";
  local image_file=${_IMAGE_FILE};
  local image_file_size=${_IMAGE_FILE_SIZE};
  
  touch $image_file;
  fallocate -l ${image_file_size} ${image_file}
  parted_disk_setup ${image_file} 
}

loopback_image_file(){
  echo_info "$FUNCNAME";
  local image_file=${_IMAGE_FILE};
  local loop_device=$(losetup -P -f --show "${image_file}");
  partprobe ${loop_device};
  
  #declare -xr _BLOCK_DEVICE_BOOT="${loop_device}p1" 
  #declare -xr _BLOCK_DEVICE_ROOT="${loop_device}p2" 
  _BLOCK_DEVICE_BOOT="${loop_device}p1" 
  _BLOCK_DEVICE_ROOT="${loop_device}p2"
}

####MISC FUNCTIONS####

#makes a luks container and formats the disk/image
#also mounts the chroot directory ready for copying
format_filesystem(){
  echo_info "$FUNCNAME";

  # Create LUKS
  echo_debug "Attempting to create LUKS ${_BLOCK_DEVICE_ROOT} "
  echo "${_LUKS_PASSWORD}" | cryptsetup -v --cipher ${_LUKS_CONFIGURATION} luksFormat ${_BLOCK_DEVICE_ROOT}
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})

  make_filesystem "vfat" "${_BLOCK_DEVICE_BOOT}"
  make_filesystem "${_FILESYSTEM_TYPE}" "${_ENCRYPTED_VOLUME_PATH}"
  
  sync
}

# Check if btrfs is the file system, if so install required packages
filesystem_setup(){
  fs_type="${_FILESYSTEM_TYPE}"
  
  case $fs_type in
    "btrfs") 
      echo_debug "- Setting up btrfs-progs on build machine"
      echo_debug "- Setting up btrfs-progs in chroot"
      chroot_package_install btrfs-progs
      echo_debug "- Adding btrfs module to initramfs-tools/modules"
      atomic_append "btrfs" "${_CHROOT_DIR}/etc/initramfs-tools/modules";
      echo_debug "- Enabling journalling"
      sed -i "s|rootflags=noload|""|g" "${_CHROOT_DIR}/boot/cmdline.txt";
      ;;
    *) echo_debug "skipping, fs not supported or ext4";;
  esac
  
  #setup btrfs here 
  #https://rootco.de/2018-01-19-opensuse-btrfs-subvolumes/
}

#formats the disk or image
parted_disk_setup()
{
  echo_info "$FUNCNAME";
  parted $1 --script -- mklabel msdos
  parted $1 --script -- mkpart primary fat32 0 256
  parted $1 --script -- mkpart primary 256 -1
  sync;
}

#calls mkfs for a given filesystem
# arguments: a filesystem type, e.g. btrfs, ext4 and a device
make_filesystem(){
  echo_info "$FUNCNAME";
  local fs_type=$1
  local device=$2
  case $fs_type in
    "vfat") mkfs.vfat $device; echo_debug "created vfat partition on $device";;
    "ext4") mkfs.ext4 $device; echo_debug "created ext4 partition on $device";;
    "btrfs")
            apt-get -qq install btrfs-progs
            mkfs.btrfs -f -L btrfs $device; echo_debug "created btrfs partition on $device"
            ;;
            
    *) exit 1;;
  esac
}
#gets from local filesystem or generates a ssh key and puts it on the build 
create_ssh_key(){
  echo_info "$FUNCNAME";
  local id_rsa="${_FILE_DIR}/id_rsa";
  
  if [ ! -f "${id_rsa}" ]; then 
    echo_debug "generating ${id_rsa}";
    ssh-keygen -b "${_SSH_BLOCK_SIZE}" -N "${_SSH_KEY_PASSPHRASE}" -f "${id_rsa}" -C "root@${_HOSTNAME}";
  fi
  
  chmod 600 "${id_rsa}";
  chmod 644 "${id_rsa}.pub";
  echo_debug "copying keyfile ${id_rsa} to box's default user .ssh directory";
  mkdir -p "${_CHROOT_DIR}/root/.ssh/" || true
  cp -p "${id_rsa}" "${_CHROOT_DIR}/root/.ssh/id_rsa";
  cp -p "${id_rsa}.pub" "${_CHROOT_DIR}/root/.ssh/id_rsa.pub";        
}

#puts the sshkey into your files directory for safe keeping
backup_dropbear_key(){
  echo_info "$FUNCNAME";
  local temporary_keypath=${1};
  local temporary_keyname="${_FILE_DIR}"/"$(basename ${temporary_keypath})";

  #if theres a key in your files directory copy it into your chroot directory
  # if there isn't, copy it from your chroot directory into your files directory
  if [ -f "${temporary_keyname}" ]; then
    cp -p "${temporary_keyname}" "${temporary_keypath}";
    chmod 600 "${temporary_keypath}";
  else
    cp -p "${temporary_keypath}" "${temporary_keyname}";
  fi
}

#rsync for local copy
#arguments $1 - to $2 - from
rsync_local(){
  echo_info "$FUNCNAME";
  echo_info "starting copy of ${@}";
  if rsync --hard-links --archive --partial --info=progress2 "${@}"; then
    echo_info "finished copy of ${@}";
    sync;
  else
    echo_error 'rsync has failed';
    exit 1;
  fi
}

arm_setup(){
  echo_info "$FUNCNAME";
  cp /usr/bin/qemu-aarch64-static ${_CHROOT_DIR}/usr/bin/
}

mount_chroot(){
  check_directory_and_mount "${_ENCRYPTED_VOLUME_PATH}" "${_CHROOT_DIR}"
  check_directory_and_mount "${_BLOCK_DEVICE_BOOT}" "${_CHROOT_DIR}/boot"
}

####CHROOT FUNCTIONS####
#mount dev,sys,proc in chroot so they are available for apt 
disk_chroot_setup(){
  local chroot_dir="${_CHROOT_DIR}"
  echo_info "$FUNCNAME";
 
  sync
  # mount binds
  check_mount_bind "/dev" "${chroot_dir}/dev/"; 
  check_mount_bind "/dev/pts" "${chroot_dir}/dev/pts";
  check_mount_bind "/sys" "${chroot_dir}/sys/";
  check_mount_bind "/tmp" "${chroot_dir}/tmp/";
  check_mount_bind "/run" "${chroot_dir}/run/";

  #procs special, so it does it a different way
  if [[ $(mount -t proc "/proc" "${chroot_dir}/proc/"; echo $?) != 0 ]]; then
      echo_error "failure mounting ${chroot_dir}/proc/";
      exit 1;
  fi

}

#unmount dev,sys,proc in chroot
disk_chroot_teardown(){
  echo_info "$FUNCNAME";
  local chroot_dir="${_CHROOT_DIR}"

  echo_debug "unmounting binds"
  tidy_umount "${chroot_dir}/dev/"
  tidy_umount "${chroot_dir}/sys/"
  tidy_umount "${chroot_dir}/proc/"
  tidy_umount "${chroot_dir}/tmp/"  
  tidy_umount "${chroot_dir}/run/"  
}

#run apt update
disk_chroot_update_apt_setup(){
  #Force https on initial use of apt for the main kali repo
  echo_info "$FUNCNAME";
  local chroot_root="${_CHROOT_DIR}"
  sed -i 's|http:|https:|g' ${chroot_root}/etc/apt/sources.list;

  if [ ! -f "${chroot_root}/etc/resolv.conf" ]; then
      echo_warn "${chroot_root}/etc/resolv.conf does not exist";
      echo_warn "Setting nameserver to $_DNS1 and $_DNS2 in ${chroot_root}/etc/resolv.conf";
      echo -e "nameserver $_DNS1\nnameserver $_DNS2" > "${chroot_root}/etc/resolv.conf";
  fi

  echo_debug "Updating apt-get";
  chroot_execute apt-get -qq update;
  
  #Corrupt package install fix code
  if [[ $(chroot_execute apt --fix-broken -qq -y install ; echo $?) != 0 ]]; then
    if [[ $(chroot_execute dpkg --configure -a ; echo $?) != 0 ]]; then
        echo_error "apt corrupted, manual intervention required";
        exit 1;
    fi
  fi
}

#installs packages from build
#arguments: a list of packages
chroot_package_install(){
  PACKAGES="$@"
  for package in $PACKAGES
  do
    echo_info "installing $package";
    chroot_execute apt-get -qq -y install $package 
  done
}

#removes packages from build
#arguments: a list of packages
chroot_package_purge(){
  PACKAGES="$@"
  for package in $PACKAGES
  do
    echo_info "purging $package";
    chroot_execute apt-get -qq -y purge $package 
  done
  chroot_execute apt-get -qq -y autoremove
} 

#run a command in chroot
chroot_execute(){
  local chroot_dir="${_CHROOT_DIR}";
  chroot ${chroot_dir} "$@" | tee -a $_LOG_FILE;
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
    echo_error "command in chroot failed"
    exit 1;
  fi
}

disk_chroot_mkinitramfs_setup(){
  local chroot_dir="${_CHROOT_DIR}"
  echo_info "$FUNCNAME";
  
  local kernel_version=$(ls ${chroot_dir}/lib/modules/ | grep "${_KERNEL_VERSION_FILTER}" | tail -n 1);
  echo_debug "kernel is '${kernel_version}'";
  
  echo_debug "running update-initramfs, mkinitramfs"
  chroot_execute update-initramfs -u -k all
  chroot_execute mkinitramfs -o /boot/initramfs.gz -v ${kernel_version}
}

####PRINT FUNCTIONS####
echo_error(){ echo -e "${_COLOR_ERROR}$(date '+%H:%M:%S'): ERROR: $*${_COLOR_NORMAL}" | tee -a ${_LOG_FILE};}
echo_warn(){ echo -e "${_COLOR_WARN}$(date '+%H:%M:%S'): WARNING: $@${_COLOR_NORMAL}" | tee -a ${_LOG_FILE};}
echo_info(){ echo -e "${_COLOR_INFO}$(date '+%H:%M:%S'): INFO: $@${_COLOR_NORMAL}" | tee -a ${_LOG_FILE};}
echo_debug(){
  if [ $_LOG_LEVEL -lt 1 ]; then
    echo -e "${_COLOR_DEBUG}$(date '+%H:%M:%S'): DEBUG: $@${_COLOR_NORMAL}";
  fi
  #even if output is suppressed by log level output it to the log file
  echo "$(date '+%H:%M:%S'): $@" >> "${_LOG_FILE}";
}

####HELPER FUNCTIONS####
#appends config to a file after checking if it's already in the file
#$1 the config value $2 the filename
atomic_append(){
  CONFIG="$1";
  FILE="$2";
  if [[ ! $(grep -w "${CONFIG}" "${FILE}") ]]; then
    echo "${CONFIG}" >> "${FILE}";
  fi
}

#checks if a variable is set or empty ''
check_variable_is_set(){
  if [[ ! ${1} ]] || [[ -z "${1}" ]]; then
    echo_debug "variable is not set or is empty";
    echo '1';
    return;
  fi
  echo '0';
}

#mounts a bind, exits on failure
check_mount_bind(){
  # mount a bind
  if [[ "$(mount -o bind $1 $2; echo $?)" != 0 ]]; then
    echo_error "failure mounting $2";
    exit 1;
  fi
}

#mounts 1=$1 to $2, creates folder if not there
check_directory_and_mount(){
  echo_debug "mounting $1 to $2";
  if [[ ! -d "$2" ]]; then 
    mkdir "$2";
    echo_debug "created $2";
  fi
  
  if [[ "$(mount $1 $2; echo $?)" != 0 ]]; then
    echo_error "failure mounting $1 to $2";
    exit 1;
  fi
  echo_debug "mounted $1 to $2";
}

#unmounts and tidies up the folder
tidy_umount(){
  if umount -q -R $1; then
    echo_info "umounted $1";
    
    if [[ -b $1 ]]; then echo_debug "block device, return"; return 0; fi

    if grep '/dev'  <<< "$1" ; then echo_debug "bind for chroot, return"; return 0; fi
    if grep '/sys'  <<< "$1" ; then echo_debug "bind for chroot, return"; return 0; fi
    if grep '/proc' <<< "$1" ; then echo_debug "bind for chroot, return"; return 0; fi
    if grep '/tmp'  <<< "$1" ; then echo_debug "bind for chroot, return"; return 0; fi
    if grep '/run'  <<< "$1" ; then echo_debug "bind for chroot, return"; return 0; fi
    
    if [[ -d $1 ]]; then echo_debug "some directory, if empty delete it"; rmdir $1 || true; fi
    return 0    
  fi
  
  echo_debug "failed to umount $1";
  return 1  
}

#runs through the functions specified in optional_setup
#checks if each function in options.sh has a requires comment
#of the form '#requires: ???'
#TODO check optional running order for 'optional' requirements
dependency_check(){
  echo_info "$FUNCNAME";
  #get list of functions specified in optional_setup:
  functions_in_optional_setup=$(sed -n '/optional_setup(){/,/}/p' env.sh | sed '/optional_setup(){/d' | sed '/}/d' | sed 's/^[ \t]*//g' | sed '/^#/d' | cut -d';' -f1 | tr '\n' ' ')
  echo_debug "$functions_in_optional_setup";
  for function in $functions_in_optional_setup; do
    line_above_function_declaration=$(grep -B 1 "${function}()" options.sh | grep -v "${function}()")    
    
    if grep -q '^#requires:' <<< $line_above_function_declaration || grep -q 'optional:' <<< $line_above_function_declaration; then 
      echo_info "$function";
    fi
    
    if grep -q '^#requires:' <<< $line_above_function_declaration; then 
      list_of_prerequisites=$(echo $line_above_function_declaration | cut -d':' -f2 | sed 's/^[ \t]*//g' | cut -d',' -f1)
      if [[ -z $list_of_prerequisites ]]; then 
        echo_info " - requires: $list_of_prerequisites" 
      fi
      for prerequisite in $list_of_prerequisites; do 
      #check the prerequisite occurs before the function in $functions_in_optional_setup
        int_position_of_prereq=$(get_position_in_array "$functions_in_optional_setup" "$prerequisite")
        if [[ -z "$int_position_of_prereq" ]]; then 
          echo_error "$prerequisite for $function is missing";
          exit 1;
        fi
        int_position_of_function=$(get_position_in_array "$functions_in_optional_setup" "$function")
        echo_debug $int_position_of_prereq
        echo_debug $int_position_of_function
        if (($int_position_of_prereq > $int_position_of_function )); then
          echo_error "$prerequisite is called after $function in optional_setup(), please amend function order"#
          exit 1;
        fi
      done
     fi
     
     if grep -q 'optional:' <<< $line_above_function_declaration; then 
       list_of_optional_prerequisites=$(echo $line_above_function_declaration | cut -d':' -f3 | sed 's/^[ \t]*//g')
       if [[ -z $list_of_optional_prerequisites ]]; then 
         echo_info " - optionally requires: $list_of_optional_prerequisites"
       fi
       for prerequisite in $list_of_optional_prerequisites; do 
          #check the prerequisite occurs before the function in $functions_in_optional_setup
          int_position_of_prereq=$(get_position_in_array "$functions_in_optional_setup" "$prerequisite")
          if [[ -z "$int_position_of_prereq" ]]; then 
            echo_warn "optional $prerequisite for $function is missing";
          fi
          int_position_of_function=$(get_position_in_array "$functions_in_optional_setup" "$function")
          echo_debug $int_position_of_prereq
          echo_debug $int_position_of_function
          if (($int_position_of_prereq > $int_position_of_function )); then
            echo_error "$prerequisite is called after $function in optional_setup(), please amend function order"
            exit 1;
          fi
       done
     fi
  done
  
}

#returns an index of a value in an array
get_position_in_array(){
  my_array=($1)
  value="$2"

  for i in "${!my_array[@]}"; do
    if [[ "${my_array[$i]}" = "${value}" ]]; then
        echo "${i}";
    fi
  done
}
