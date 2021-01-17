#!/bin/bash
# shellcheck disable=SC2128
# shellcheck disable=SC2034
# shellcheck disable=SC2145
# shellcheck disable=SC2086
# shellcheck disable=SC2068
set -eu

#Global variables
export _BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";
export _BUILD_DIR=${_BASE_DIR}/build
export _FILE_DIR=${_BASE_DIR}/files
export _EXTRACTED_IMAGE="${_FILE_DIR}/extracted.img"
export _CHROOT_ROOT=${_BUILD_DIR}/root
export _DISK_CHROOT_ROOT=${_BUILD_DIR}/disk
export _ENCRYPTED_VOLUME_PATH="/dev/mapper/crypt-2"
export _COLOR_ERROR='\033[0;31m' #red
export _COLOR_WARN='\033[1;33m' #orange
export _COLOR_INFO='\033[0;35m' #purple
export _COLOR_DEBUG='\033[0;37m' #grey
export _COLOR_NORMAL='\033[0m' # No Color
export _LOG_FILE="${_BASE_DIR}/build-$(date '+%Y-%m-%d-%H:%M:%S').log"
export _IMAGE_FILE="${_BUILD_DIR}/image.img"
export _IMAGE_FILE_SIZE="11G";

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
  extracted_image_loop_device=$(losetup -a | grep $_EXTRACTED_IMAGE | cut -d':' -f 1);
  image_file_loop_device=$(losetup -a | grep $_IMAGE_FILE | cut -d':' -f 1);
  
  echo_debug "deleting the folders used to mount the extracted image";
  umount "${_BUILD_DIR}/mount" || true;
  umount "${_BUILD_DIR}/boot" || true;
  rmdir ${_BUILD_DIR}/mount || true;
  rmdir ${_BUILD_DIR}/boot || true;
  
  echo_debug "unmounting tmp,dev,sys";
  disk_chroot_teardown;
  if (( $_IMAGE_MODE == 1 )); then
    echo_debug "IMAGE MODE CLEAN UP";
    cleanup_loop_device $image_file_loop_device;
    echo_warn "To burn your disk run: dd if=${_IMAGE_FILE} of=${_OUTPUT_BLOCK_DEVICE} bs=512 status=progress && sync";
  else
    echo_debug "DISK MODE CLEANUP";
    umount "${_BLOCK_DEVICE_BOOT}" || true
    umount "${_BLOCK_DEVICE_ROOT}" || true
  fi
  
  cryptsetup -v luksClose "${_ENCRYPTED_VOLUME_PATH}" || true

  echo_debug "deleting the folders used to mount the extracted image and new image";
  if umount "${_DISK_CHROOT_ROOT}"; then 
    rmdir "${_DISK_CHROOT_ROOT}" || true;
  fi
  echo_debug "clean up extracted image loop device";
  cleanup_loop_device $extracted_image_loop_device;
}

#auxiliary method for detaching loop_device in cleanup method 
cleanup_loop_device(){
  echo_info "$FUNCNAME $1";
  local loop_device=$1;
  #TODO forloop through loop devices.
  if [ ! -z ${loop_device} ]; then
    umount ${loop_device}p1 || true;
    umount ${loop_device}p2 || true;
    umount ${loop_device} || true;
    losetup -d "${loop_device}p1" || true;
    losetup -d "${loop_device}p2" || true;
    losetup -d "${loop_device}" || true;
  fi
}

#check if theres a build directory already
check_build_dir_exists(){
  #no echo as interferes with return echos
  if [ "${_NO_PROMPTS}" -eq 1 ] ; then
    echo '1';
    return;
  fi
  
  if [ -d ${_BUILD_DIR} ]; then
    local continue;
    read -p "Build directory already exists: ${_BUILD_DIR}. Rebuild Yes,No? (y/N)  " continue;
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
  if [ -z "${_OUTPUT_BLOCK_DEVICE+x}" ] || [ -z "${_OUTPUT_BLOCK_DEVICE}"  ]; then
    echo_error "No Output Block Device Set";
    exit;
  fi

  local prefix=""
  #if the device contains mmcblk, prefix is set to so the device name is picked up correctly
  if [[ "${_OUTPUT_BLOCK_DEVICE}" == *'mmcblk'* ]]; then
    prefix='p'
  fi
  #Set the proper name of the output block device's partitions
  #e.g /dev/sda1 /dev/sda2 etc.
  export _BLOCK_DEVICE_BOOT="${_OUTPUT_BLOCK_DEVICE}${prefix}1"
  export _BLOCK_DEVICE_ROOT="${_OUTPUT_BLOCK_DEVICE}${prefix}2"
}


create_build_directory_structure(){
  echo_info "$FUNCNAME";
  #TODO maybe exit out if its already there
  mkdir "${_BUILD_DIR}" || true; 
  mkdir "${_BUILD_DIR}/mount" || true; #where the extracted image's root directory is mounted
  mkdir "${_BUILD_DIR}/boot" || true;  #where the extracted image's boot directory is mounted
}

#extracts the image so it can be mounted
extract_image() {
  echo_info "$FUNCNAME";

  local image_name="$(basename ${_IMAGE_URL})";
  local image_path="${_FILE_DIR}/${image_name}";
  local extracted_image="${_EXTRACTED_IMAGE}";

  #If no prompts is set and extracted image exists then continue to extract
  if [ "${_NO_PROMPTS}" -eq 1 ]; then
    if [ -e "${extracted_image}" ]; then
      return 0;
    fi
  elif [ -e "${extracted_image}" ]; then
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
mount_image_on_loopback(){
  echo_info "$FUNCNAME";
  local extracted_image="${_EXTRACTED_IMAGE}";
  local loop_device=$(losetup -P -f --read-only --show "$extracted_image");
  partprobe ${loop_device};
  mount ${loop_device}p2 ${_BUILD_DIR}/mount;
  mount ${loop_device}p1 ${_BUILD_DIR}/boot;
}

#rsyncs the mounted image to a new folder
copy_extracted_image_to_chroot_dir(){
  echo_info "$FUNCNAME";
  rsync_local "${_BUILD_DIR}/boot" "${_DISK_CHROOT_ROOT}/"
  rsync_local "${_BUILD_DIR}/mount/"* "${_DISK_CHROOT_ROOT}"
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
  
  # Check if btrfs is the file system, if so install required packages
  fs_type="${_FILESYSTEM_TYPE}"
  if [ "$fs_type" = "btrfs" ]; then
      echo_debug "- Setting up btrfs-progs on build machine"
      apt-get -qq install btrfs-progs
      echo_debug "- Setting up btrfs-progs in chroot"
      chroot_package_install btrfs-progs
      echo_debug "- Adding btrfs module to initramfs-tools/modules"
      atomic_append "btrfs" "${_DISK_CHROOT_ROOT}/etc/initramfs-tools/modules";
      echo_debug "- Enabling journalling"
      sed -i "s|rootflags=noload|""|g" ${_DISK_CHROOT_ROOT}/boot/cmdline.txt
  fi

  chroot_package_install cryptsetup busybox

  # Creating symbolic link to e2fsck
  chroot ${_DISK_CHROOT_ROOT} /bin/bash -c "test -L /sbin/fsck.luks || ln -s /sbin/e2fsck /sbin/fsck.luks"

  # Indicate kernel to use initramfs - facilitates loading drivers
  atomic_append 'initramfs initramfs.gz followkernel' "${_DISK_CHROOT_ROOT}/boot/config.txt";
  
  # Update /boot/cmdline.txt to boot crypt
  sed -i "s|root=/dev/mmcblk0p2|root=${_ENCRYPTED_VOLUME_PATH} cryptdevice=/dev/mmcblk0p2:$(basename ${_ENCRYPTED_VOLUME_PATH})|g" ${_DISK_CHROOT_ROOT}/boot/cmdline.txt
  sed -i "s|rootfstype=ext3|rootfstype=${fs_type}|g" ${_DISK_CHROOT_ROOT}/boot/cmdline.txt
  

  # Enable cryptsetup when building initramfs
  atomic_append 'CRYPTSETUP=y' "${_DISK_CHROOT_ROOT}/etc/cryptsetup-initramfs/conf-hook"  
  
  # Update /etc/fstab
  sed -i "s|/dev/mmcblk0p2|${_ENCRYPTED_VOLUME_PATH}|g" ${_DISK_CHROOT_ROOT}/etc/fstab
  sed -i "s#ext3#${fs_type}#g" ${_DISK_CHROOT_ROOT}/etc/fstab

  # Update /etc/crypttab
  atomic_append "$(basename ${_ENCRYPTED_VOLUME_PATH})    /dev/mmcblk0p2    none    luks" "${_DISK_CHROOT_ROOT}/etc/crypttab"

  # Create a hook to include our crypttab in the initramfs
  cp -p "${_FILE_DIR}/initramfs-scripts/zz-cryptsetup" "${_DISK_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-cryptsetup";
  
  # Unlock Script
  cp -p "${_FILE_DIR}/initramfs-scripts/unlock.sh" "${_DISK_CHROOT_ROOT}/etc/initramfs-tools/unlock.sh";
  sed -i "s#ENCRYPTED_VOLUME_PATH#${_ENCRYPTED_VOLUME_PATH}#" "${_DISK_CHROOT_ROOT}/etc/initramfs-tools/unlock.sh";

  # Adding dm_mod to initramfs modules
  atomic_append 'dm_crypt' "${_DISK_CHROOT_ROOT}/etc/initramfs-tools/modules";
  
  # Disable autoresize
  chroot_execute systemctl disable rpi-resizerootfs.service
}

# Encrypt & Write SD
copy_to_disk(){  
  echo_info "$FUNCNAME";

  fs_type=$_FILESYSTEM_TYPE;
  
  echo_debug "Partitioning SD Card"
  parted  ${_OUTPUT_BLOCK_DEVICE} --script -- mklabel msdos
  parted  ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary fat32 0 256
  parted  ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary 256 -1
  sync

  # Create LUKS
  echo_debug "Attempting to create LUKS ${_BLOCK_DEVICE_ROOT} "
  
  #TODO check ${_ENCRYPTED_VOLUME_PATH} already exists, if it does
  echo_debug "$(dmsetup ls --target crypt | grep ${_ENCRYPTED_VOLUME_PATH})"
  # warn and ask to overwrite
  
  echo "${_LUKS_PASSWORD}" | cryptsetup -v --cipher ${_LUKS_CONFIGURATION} luksFormat ${_BLOCK_DEVICE_ROOT}
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})

  make_filesystem "vfat" "${_BLOCK_DEVICE_BOOT}"
  make_filesystem "${fs_type}" "${_ENCRYPTED_VOLUME_PATH}"

  # Mount LUKS
  echo_debug "Mounting ${_ENCRYPTED_VOLUME_PATH} to ${_DISK_CHROOT_ROOT}"
  if [ ! -d ${_DISK_CHROOT_ROOT} ]; then 
    mkdir ${_DISK_CHROOT_ROOT};
  fi
  mount ${_ENCRYPTED_VOLUME_PATH} ${_DISK_CHROOT_ROOT} && echo_debug "- Mounted ${_ENCRYPTED_VOLUME_PATH} to ${_DISK_CHROOT_ROOT}"

  # Mount boot partition
  echo_debug "Attempting to mount ${_BLOCK_DEVICE_BOOT} to ${_DISK_CHROOT_ROOT}/boot "
  
  if [ ! -d "${_DISK_CHROOT_ROOT}/boot" ]; then 
    mkdir "${_DISK_CHROOT_ROOT}/boot";
  fi
  mount ${_BLOCK_DEVICE_BOOT} ${_DISK_CHROOT_ROOT}/boot && echo_debug "- Mounted ${_BLOCK_DEVICE_BOOT} to ${_DISK_CHROOT_ROOT}/boot"

  # Attempt to copy files from build to mounted device
  sync
}

#makes an image file instead of copying to a disk
copy_to_image_file(){
  echo_info "$FUNCNAME";

  local fs_type=$_FILESYSTEM_TYPE;
  local image_file=${_IMAGE_FILE};
  local image_file_size=${_IMAGE_FILE_SIZE};
  local loop_device=$(losetup -P -f --show "${image_file}");
  partprobe ${loop_device};
  local block_device_boot="${loop_device}p1" 
  local block_device_root="${loop_device}p2" 
  
  fallocate -l ${image_file_size} ${image_file}

  #TODO check for existing image
  echo_debug "Partitioning Image"
  parted ${image_file} --script -- mklabel msdos
  parted ${image_file} --script -- mkpart primary fat32 0 256
  parted ${image_file} --script -- mkpart primary 256 -1
  sync
  
  #TODO check ${_ENCRYPTED_VOLUME_PATH} already exists, if it does
  echo_debug "$(dmsetup ls --target crypt | grep ${_ENCRYPTED_VOLUME_PATH})"
  # warn and ask to overwrite
  
  # Create LUKS
  echo_debug "Attempting to create LUKS ${block_device_root} "
  echo "${_LUKS_PASSWORD}" | cryptsetup -v --cipher ${_LUKS_CONFIGURATION} luksFormat ${block_device_root}
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${block_device_root} $(basename ${_ENCRYPTED_VOLUME_PATH})

  make_filesystem "vfat" "${block_device_boot}"
  make_filesystem "${fs_type}" "${_ENCRYPTED_VOLUME_PATH}"

  # Mount LUKS
  echo_debug "Mounting ${_ENCRYPTED_VOLUME_PATH} to ${_DISK_CHROOT_ROOT}"
  if [ ! -d ${_DISK_CHROOT_ROOT} ]; then 
    mkdir ${_DISK_CHROOT_ROOT};
  fi
  mount ${_ENCRYPTED_VOLUME_PATH} ${_DISK_CHROOT_ROOT} && echo_debug "- Mounted ${_ENCRYPTED_VOLUME_PATH} to ${_DISK_CHROOT_ROOT}"

  # Mount boot partition
  echo_debug "Attempting to mount ${block_device_boot} to ${_DISK_CHROOT_ROOT}/boot "
  
  if [ ! -d "${_DISK_CHROOT_ROOT}/boot" ]; then 
    mkdir "${_DISK_CHROOT_ROOT}/boot";
  fi
  mount ${block_device_boot} ${_DISK_CHROOT_ROOT}/boot && echo_debug "- Mounted ${block_device_boot} to ${_DISK_CHROOT_ROOT}/boot"

  # Attempt to copy files from build to mounted device
  sync
}


#### MISC FUNCTIONS####

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
  mkdir -p "${_DISK_CHROOT_ROOT}/root/.ssh/" || true
  cp -p "${id_rsa}" "${_DISK_CHROOT_ROOT}/root/.ssh/id_rsa";
  cp -p "${id_rsa}.pub" "${_DISK_CHROOT_ROOT}/root/.ssh/id_rsa.pub";        
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

#calls mkfs for a given filesystem
# arguments: a filesystem type, e.g. btrfs, ext4 and a device
make_filesystem(){
  echo_info "$FUNCNAME";
  local fs_type=$1
  local device=$2
  case $fs_type in
    "vfat") mkfs.vfat $device; echo_debug "created vfat partition on $device";;
    "ext4") mkfs.ext4 $device; echo_debug "created ext4 partition on $device";;
    "btrfs") mkfs.btrfs -f -L btrfs $device; echo_debug "created btrfs partition on $device";;
    *) exit 1;;
  esac
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

####CHROOT FUNCTIONS####

#mount dev,sys,proc in chroot so they are available for apt 
disk_chroot_setup(){
  local chroot_dir="${_DISK_CHROOT_ROOT}"
  
  #TODO new method needed for this
  cp /usr/bin/qemu-aarch64-static ${_DISK_CHROOT_ROOT}/usr/bin/

  echo_info "$FUNCNAME";
  # mount binds
  if [[ "$(mount -o bind /dev "${chroot_dir}/dev/"; echo $?)" != 0 ]]; then
    echo_error "failure mounting ${chroot_dir}/dev/";
    exit 1;
  fi
  
  if [[ $(mount -o bind /dev/pts "${chroot_dir}/dev/pts"; echo $?) != 0 ]]; then
    echo_error "failure mounting ${chroot_dir}/dev/pts";
    exit 1;
  fi
  
  if [[ $(mount -o bind /sys "${chroot_dir}/sys/"; echo $?) != 0 ]]; then
    echo_error "failure mounting ${chroot_dir}/sys/";
    exit 1;
  fi
  
  if [[ $(mount -t proc /proc "${chroot_dir}/proc/"; echo $?) != 0 ]]; then
    echo_error "failure mounting ${chroot_dir}/proc/";
    exit 1;
  fi
  
  if [[ $(mount -o bind /tmp "${chroot_dir}/tmp/"; echo $?) != 0 ]]; then
    echo_error "failure mounting ${chroot_dir}/tmp/";
    exit 1;
  fi
}

#unmount dev,sys,proc in chroot
disk_chroot_teardown(){
  echo_info "$FUNCNAME";
  local chroot_dir="${_DISK_CHROOT_ROOT}"

  echo_debug "unmounting binds"
  if umount -R "${chroot_dir}/dev/"; then
    echo_info "umounting ${chroot_dir}/dev/";
  else
    echo_warn "problem umounting ${chroot_dir}/dev/ or was already umounted";
  fi
  
  if umount "${chroot_dir}/sys/"; then
    echo_info "umounting ${chroot_dir}/sys/";
  else
    echo_warn "problem umounting ${chroot_dir}/sys/ or was already umounted";
  fi
  
  if umount "${chroot_dir}/proc/"; then
    echo_info "umounting ${chroot_dir}/proc/";
  else
    echo_warn "problem umounting ${chroot_dir}/proc/ or was already umounted";
  fi
  
  if umount "${chroot_dir}/tmp/"; then
    echo_info "umounting ${chroot_dir}/tmp/";
  else
    echo_warn "problem umounting ${chroot_dir}/tmp/ or was already umounted";
  fi
}

#run apt update
disk_chroot_update_apt_setup(){
  #Force https on initial use of apt for the main kali repo
  echo_info "$FUNCNAME";
  local chroot_root="${_DISK_CHROOT_ROOT}"
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
  chroot_execute apt-get -qq -y autoremove ;
} 

#run a command in chroot
#TODO log messages from chroot_execute
chroot_execute(){
  local chroot_dir="${_DISK_CHROOT_ROOT}";
  chroot ${chroot_dir} "$@";
  if [ $? -ne 0 ]; then
    echo_error "command in chroot failed"
    exit 1;
  fi
}

disk_chroot_mkinitramfs_setup(){
  local chroot_dir="${_DISK_CHROOT_ROOT}"
  echo_info "$FUNCNAME";
  
  local kernel_version=$(ls ${chroot_dir}/lib/modules/ | grep "${_KERNEL_VERSION_FILTER}" | tail -n 1);
  echo_debug "kernel is '${kernel_version}'";
  
  echo_debug "running update-initramfs, mkinitramfs"
  chroot_execute update-initramfs -u -k all;
  chroot_execute mkinitramfs -o /boot/initramfs.gz -v ${kernel_version};
}

####PRINT FUNCTIONS####
echo_error(){ echo -e "${_COLOR_ERROR}$(date '+%H:%M:%S'): ERROR: $*${_COLOR_NORMAL}" | tee -a ${_LOG_FILE};}
echo_warn(){  echo -e "${_COLOR_WARN}$(date '+%H:%M:%S'): WARNING: $@${_COLOR_NORMAL}" | tee -a ${_LOG_FILE};}
echo_info(){  echo -e "${_COLOR_INFO}$(date '+%H:%M:%S'): INFO: $@${_COLOR_NORMAL}" | tee -a ${_LOG_FILE};}
echo_debug(){
  if [ $_LOG_LEVEL -lt 1 ]; then
    echo -e "${_COLOR_DEBUG}$(date '+%H:%M:%S'): DEBUG: $@${_COLOR_NORMAL}";
  fi
  #even if output is suppressed by log level output it to the log file
  echo "$(date '+%H:%M:%S'): $@" >> "${_LOG_FILE}";
}

#####HELPER FUNCTIONS#####
#appends config to a file after checking if it's already in the file
#$1 the config value $2 the filename
atomic_append(){
  CONFIG="$1";
  FILE="$2";
  if [[ ! $(grep -w "${CONFIG}" "${FILE}") ]]; then
    echo "${CONFIG}" >> "${FILE}";
  fi
}
