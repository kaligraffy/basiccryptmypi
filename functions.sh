#!/bin/bash
# shellcheck disable=SC2034
# shellcheck disable=SC2145
set -eu

export _BUILD_DIR=${_BASEDIR}/build
export _FILE_DIR=${_BASEDIR}/files
export _CHROOT_ROOT=${_BUILD_DIR}/root
export _DISK_CHROOT_ROOT=/mnt/cryptmypi
export _ENCRYPTED_VOLUME_PATH="/dev/mapper/crypt-1"
export _COLOR_ERROR='\033[0;31m' #red
export _COLOR_WARN='\033[1;33m' #orange
export _COLOR_INFO='\033[0;35m' #purple
export _COLOR_DEBUG='\033[0;37m' #grey
export _COLOR_NORMAL='\033[0m' # No Color
export _IMAGE_PREPARATION_STARTED=0;
export _WRITE_TO_DISK_STARTED=0;
export _LOG_FILE_PATH=${_BUILD_DIR}
export _LOG_FILE="build-$(date '+%Y-%m-%d-%H:%M:%S').log"

# Runs on script exit, tidies up the mounts.
trap_on_error() {
  echo_error "error on line $1";
  exit 1;
}

# Runs on script exit, tidies up the mounts.
trap_on_interrupt() {
  echo_error "script interrupted by user";
  exit 1;
}

# Runs on script exit, tidies up the mounts.
trap_on_exit() {
  if (( $_IMAGE_PREPARATION_STARTED > 0 )); then cleanup_image_prep; fi
  if (( $_WRITE_TO_DISK_STARTED > 0 )); then cleanup_write_disk; fi
  echo_info "stopping $(basename $0) at $(date)";
}

# Check preconditions
check_preconditions(){
    echo_info "$FUNCNAME started at $(date)"
    # Precondition check for root powers
    check_root;
} 

check_build_dir_exists(){
    if [  -d ${_BUILD_DIR} ]; then
        echo_warn "Build directory already exists: ${_BUILD_DIR}";
        local continue;
        read -p "Clean old build and rebuild? (y/N)" continue;
        if [ "${continue}" = 'y' ] || [ "${continue}" = 'Y' ]; then
            rm -rf ${_BUILD_DIR} || true ;
        else
            return 0;
        fi
    fi
}

# Encrypt & Write SD
setup_filesystem_and_copy_to_disk(){  
  
  echo_info "$FUNCNAME started at $(date) ";
  fs_type=$_FILESYSTEM_TYPE;
  check_disk_is_correct;
  cleanup_write_disk
  
  cryptsetup luksClose ${_ENCRYPTED_VOLUME_PATH} || true
  echo_debug "Partitioning SD Card"
  parted ${_OUTPUT_BLOCK_DEVICE} --script -- mklabel msdos
  parted --align optimal ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary fat32 0 256
  parted --align optimal${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary 256 -1
  sync

  # Create LUKS
  echo_debug "Attempting to create LUKS ${_BLOCK_DEVICE_ROOT} "
  echo "${_LUKS_PASSWORD}" | cryptsetup -v --cipher ${_LUKS_CONFIGURATION} luksFormat ${_BLOCK_DEVICE_ROOT}
  echo_debug "LUKS created ${_BLOCK_DEVICE_ROOT} "

  echo_debug "Attempting to open LUKS ${_BLOCK_DEVICE_ROOT} "
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} $(basename ${_ENCRYPTED_VOLUME_PATH})
  echo_debug "- LUKS open"

  make_filesystem "vfat" "${_BLOCK_DEVICE_BOOT}"
  make_filesystem "${fs_type}" "${_ENCRYPTED_VOLUME_PATH}"

  # Mount LUKS
  echo_debug "Mounting ${_ENCRYPTED_VOLUME_PATH} to ${_DISK_CHROOT_ROOT}"
  mkdir ${_DISK_CHROOT_ROOT}
  mount ${_ENCRYPTED_VOLUME_PATH} ${_DISK_CHROOT_ROOT} && echo_debug "- Mounted ${_ENCRYPTED_VOLUME_PATH} to ${_DISK_CHROOT_ROOT}"

  # Mount boot partition
  echo_debug "Attempting to mount ${_BLOCK_DEVICE_BOOT} to ${_DISK_CHROOT_ROOT}/boot "
  mkdir ${_DISK_CHROOT_ROOT}/boot
  mount ${_BLOCK_DEVICE_BOOT} ${_DISK_CHROOT_ROOT}/boot && echo_debug "- Mounted ${_BLOCK_DEVICE_BOOT} to ${_DISK_CHROOT_ROOT}/boot"

  # Attempt to copy files from build to mounted device
  rsync_local "${_CHROOT_ROOT}"/* "${_DISK_CHROOT_ROOT}"
  chroot_mount "${_DISK_CHROOT_ROOT}"
  chroot_mkinitramfs ${_DISK_CHROOT_ROOT}
  chroot_umount "${_DISK_CHROOT_ROOT}" || true

  # Close LUKS
  cryptsetup -v luksClose "${_ENCRYPTED_VOLUME_PATH}" 

  # Clean up
  rmdir ${_DISK_CHROOT_ROOT}
  sync
}

# Cleanup on exit
cleanup_image_prep(){
  umount  "${_BUILD_DIR}/mount" || true
  umount  "${_BUILD_DIR}/boot" || true
  losetup -D || true
  rm -rf ${_BUILD_DIR}/mount || true
  rm -rf ${_BUILD_DIR}/boot || true
}
# Cleanup on exit
cleanup_write_disk(){
  umount ${_OUTPUT_BLOCK_DEVICE}* || true
  umount ${_DISK_CHROOT_ROOT} || true
  umount ${_ENCRYPTED_VOLUME_PATH} || true
  [ -d ${_DISK_CHROOT_ROOT} ] && rmdir ${_DISK_CHROOT_ROOT} || true
  cryptsetup luksClose $_ENCRYPTED_VOLUME_PATH || true
}

call_hooks(){
  local hookop="${1}"
  # shellcheck disable=SC2004
  for hook in ${_BASEDIR}/hooks/????-${hookop}*
  do
    if [ -e ${hook} ]; then
      echo_info "- calling $(basename ${hook}) "
      . ${hook}
    fi
  done
}

#checks if script was run with root
check_root(){
  if (( $EUID != 0 )); then
    echo_error "This script must be run as root/sudo"
    exit 1
  fi
}

#Fix for using mmcblk0pX devices, adds a p used later on
fix_block_device_names(){
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
  mkdir "${_BUILD_DIR}" 
  mkdir -p "${_FILE_DIR}" #where images are downloaded, extracted image lives here too
  mkdir "${_BUILD_DIR}/mount" #where the extracted image's root directory is mounted
  mkdir "${_BUILD_DIR}/boot"  #where the extracted image's root directory is mounted
  mkdir "${_CHROOT_ROOT}" #where the extracted image's files are copied to to be editted
}

extract_image() {
  local image_name=$(basename ${_IMAGE_URL})
  local image_path="${_FILE_DIR}/${image_name}"
  local extracted_image="${_FILE_DIR}/extracted.img"
  #export path to image file into the environment so other functions can use it later
  export EXTRACTED_IMAGE="${extracted_image}"
  
  #Check if you want to re-extract the image you downloaded, if it exists
  if [ -e "$extracted_image" ]; then
    local continue="";
    read -p "$extracted_image found, re-extract? (y/N)" continue;
    if [ "${continue}" != 'y' ] || [ "${continue}" != 'Y' ]; then
      return 0;
    fi
  fi

  echo_info "Starting extract at $(date)"
  case ${image_path} in
    *.xz)
        echo_info "Extracting with xz"
        #If theres a problem extracting, delete the partially extracted file and exit
        trap "rm $extracted_image; exit 1" ERR SIGINT
        pv ${image_path} | xz --decompress --stdout > "$extracted_image"
        trap - ERR SIGINT
        ;;
    *.zip)
        echo_info "Extracting with unzip"
        unzip -p $image_path > "$extracted_image"
        ;;
    *)
        echo_error "Unknown extension type on image: $image_path"
        exit 1
        ;;
  esac
  
  echo_info "Finished extract at $(date)"
}

copy_extracted_image_to_chroot_dir(){
  echo_debug "Mounting loopback";
  local extracted_image="${EXTRACTED_IMAGE}"
    loopdev=$(losetup -P -f --show "$extracted_image");
    partprobe ${loopdev};
    mount ${loopdev}p2 ${_BUILD_DIR}/mount
    mount ${loopdev}p1 ${_BUILD_DIR}/boot
    rsync_local "${_BUILD_DIR}/boot" "${_CHROOT_ROOT}/"
    if [ ! -e  "${_CHROOT_ROOT}/boot" ]; then
      echo_error 'rsync has failed'
      exit;
    fi
    rsync_local "${_BUILD_DIR}/mount/"* "${_CHROOT_ROOT}"
    if [ ! -e  "${_CHROOT_ROOT}/var" ]; then
      echo_error 'rsync has failed'
      exit;
    fi
}

check_disk_is_correct(){
  local continue
  echo_warn "CHECK DISK IS CORRECT"
  echo_info "$(lsblk)"
  echo_info ""
  read -p "Type 'YES' if the selected device is correct:  ${_OUTPUT_BLOCK_DEVICE}" continue
  if [ "${continue}" != 'YES' ] ; then
      exit 0
  fi
}

chroot_mount(){
  local chroot_dir=$1
  echo_debug "Preparing chroot mount structure at '${chroot_dir}'."
  # mount binds
  echo_debug "Mounting '${chroot_dir}/dev/' "
  mount --bind /dev ${chroot_dir}/dev/ || echo_error "mounting '${chroot_dir}/dev/'"
  echo_debug "Mounting '${chroot_dir}/dev/pts' "
  mount --bind /dev/pts ${chroot_dir}/dev/pts || echo_error "mounting '${chroot_dir}/dev/pts'"
  echo_debug "Mounting '${chroot_dir}/sys/' ";
  mount --bind /sys ${chroot_dir}/sys/ || echo_error "mounting '${chroot_dir}/sys/'";
  echo_debug "Mounting '${chroot_dir}/proc/' ";
  mount -t proc /proc ${chroot_dir}/proc/ || echo_error "mounting '${chroot_dir}/proc/'";
}

chroot_umount(){
  local chroot_dir="$1"
  echo_debug "Unmounting binds"
  umount ${chroot_dir}/dev/pts || true;
  umount ${chroot_dir}/dev || true;
  umount ${chroot_dir}/sys || true;
  umount ${chroot_dir}/proc || true;
}

#run apt update
chroot_update(){
  #Force https on initial use of apt for the main kali repo
  local chroot_root="$1"
  sed -i 's|http:|https:|g' ${chroot_root}/etc/apt/sources.list;

  if [ ! -f "${chroot_root}/etc/resolv.conf" ]; then
      echo_warn "${chroot_root}/etc/resolv.conf does not exist";
      echo_warn "Setting nameserver to $_DNS1 and $_DNS2 in ${chroot_root}/etc/resolv.conf";
      echo -e "nameserver $_DNS1\nnameserver $_DNS2" > "${chroot_root}/etc/resolv.conf";
  fi

  echo_debug "Updating apt-get";
  chroot_execute ${chroot_root} apt-get -qq update;
}

#installs packages from build
#arguments: a list of packages
chroot_package_install(){
  local chroot_dir=$1;
  shift;
  echo_info "- Installing $@";
  chroot_execute "${chroot_dir}" apt-get -qq -y install ${1} ;
}

#removes packages from build
#arguments: a list of packages
chroot_package_purge(){
  local chroot_dir=$1;
  shift;
  echo_info "- Purging $@";
  chroot_execute "${chroot_dir}" apt-get -qq -y purge ${1} ;
  chroot_execute "${chroot_dir}" apt-get -qq -y autoremove ;
}

chroot_execute(){
  local chroot_dir=$1;
  shift;
  chroot ${chroot_dir} "$@";
}

#gets from local filesystem or generates a ssh key and puts it on the build 
assure_box_sshkey(){
  local id_rsa="${_FILE_DIR}/id_rsa";
  echo_debug "Make ssh keyfile:";
  test -f "${id_rsa}" && {
    echo_debug "- Keyfile ${id_rsa} already exists";
    } || {
    echo_debug "- Keyfile ${id_rsa} does not exists. Generating ";
    ssh-keygen -b "${_SSH_BLOCK_SIZE}" -N "${_SSH_KEY_PASSPHRASE}" -f "${id_rsa}";
    chmod 600 "${id_rsa}";
    chmod 644 "${id_rsa}.pub";
  }
  echo_debug "- Copying keyfile ${id_rsa} to box's default user .ssh directory";
  cp "${id_rsa}" "${_CHROOT_ROOT}/.ssh/id_rsa";
  cp "${id_rsa}.pub" "${_CHROOT_ROOT}/.ssh/id_rsa.pub";
  chmod 600 "${_CHROOT_ROOT}/.ssh/id_rsa";
  chmod 644 "${_CHROOT_ROOT}/.ssh/id_rsa.pub";
}

backup_and_use_sshkey(){
  local temporary_keypath=${1};
  local temporary_keyname="${_FILE_DIR}"/"$(basename ${temporary_keypath})";

  test -f "${temporary_keyname}" && {
    cp "${temporary_keyname}" "${temporary_keypath}";
    chmod 600 "${temporary_keypath}";
    } || {
    cp "${temporary_keypath}" "${temporary_keyname}";
  }
}

chroot_mkinitramfs(){
  local chroot_dir="$1"
  echo_debug "Building new initramfs (CHROOT is ${chroot_dir})";

  #Point crypttab to the current physical device during mkinitramfs
  echo_debug "  Creating symbolic links from current physical device to crypttab device (if not using sd card mmcblk0p)";
  test -e "/dev/mmcblk0p1" || (test -e "${_BLOCK_DEVICE_BOOT}" && ln -s "${_BLOCK_DEVICE_BOOT}" "/dev/mmcblk0p1");
  test -e "/dev/mmcblk0p2" || (test -e "${_BLOCK_DEVICE_ROOT}" && ln -s "${_BLOCK_DEVICE_ROOT}" "/dev/mmcblk0p2");
  # determining the kernel
  local kernel_version=$(ls ${chroot_dir}/lib/modules/ | grep "${_KERNEL_VERSION_FILTER}" | tail -n 1);
  echo_debug "kernel is '${kernel_version}'";
  chroot_execute "${chroot_dir}" update-initramfs -u -k all;
  chroot_execute "${chroot_dir}" mkinitramfs -o /boot/initramfs.gz -v ${kernel_version};

  # cleanup
  echo_debug "Cleaning up symbolic links";
  test -L "/dev/mmcblk0p1" && unlink "/dev/mmcblk0p1";
  test -L "/dev/mmcblk0p2" && unlink "/dev/mmcblk0p2";
}

#calls mkfs for a given filesystem
# arguments: a filesystem type, e.g. btrfs, ext4 and a device
make_filesystem(){
  local fs_type=$1
  local device=$2
  case $fs_type in
    "vfat") mkfs.vfat $device; echo_debug "created vfat partition on $device";;
    "ext4") mkfs.ext4 $device; echo_debug "created ext4 partition on $device";;
    "btrfs") mkfs.btrfs $device; echo_debug "created btrfs partition on $device";;
    *) exit 1;;
  esac
}

#rsync for local copy
#arguments $1 - to $2 - from
rsync_local(){
  echo_info "Starting copy of "${@}" at $(date)"
  rsync --hard-links  --archive --partial --info=progress2 "${@}"
  echo_info "Finished copy of "${@}" at $(date)"
  sync;
}

#Download an image file to the file directory
download_image(){
  local image_name=$(basename ${_IMAGE_URL})
  local image_out_file=${_FILE_DIR}/${image_name}
  echo_info "Starting download at $(date)"
  wget -nc "${_IMAGE_URL}" -O "${image_out_file}" || true
  echo_info "Completed download at $(date)"
  if [ -z ${_IMAGE_SHA256} ]; then
    return 0
  fi
  echo_info "Checking image checksum"
  echo ${_IMAGE_SHA256}  $image_out_file | sha256sum --check --status
  echo_info "- valid"
}

#Print messages
echo_error(){
  echo -e "${_COLOR_ERROR}ERROR: $*${_COLOR_NORMAL}"
}
echo_warn(){
  echo -e "${_COLOR_WARN}WARNING: $@${_COLOR_NORMAL}"
}
echo_info(){
  echo -e "${_COLOR_INFO}$@${_COLOR_NORMAL}"
}
echo_debug(){
  if [ $_LOG_LEVEL -lt 1 ]; then
    echo -e "${_COLOR_DEBUG}$@${_COLOR_NORMAL}"
  fi
  #even if output is suppressed by log level output it to the log file
  echo "$@" >> "${_LOG_FILE}"
}
