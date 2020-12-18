#!/bin/bash
# shellcheck disable=SC2034
# shellcheck disable=SC2145
set -e
set -u

_COLOR_ERROR='\033[0;31m'
_COLOR_WARN='\033[1;33m'
_COLOR_INFO='\033[0;35m'
_COLOR_DEBUG='\033[0;37m'
_COLOR_NORMAL='\033[0m' # No Color

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
}

# Cleanup on exit
cleanup(){
    chroot_umount || true
    umount ${_OUTPUT_BLOCK_DEVICE}* || true
    umount -l ${_CHROOT_ROOT} || true
    umount -f ${_ENCRYPTED_VOLUME_PATH} || true
    [ -d ${_CHROOT_ROOT} ] && rm -r ${_CHROOT_ROOT} || true
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

# Check preconditions
check_preconditions(){
    echo_info "$FUNCNAME started at $(date)"
    # Precondition check for root powers
    check_root;
    fix_block_device_names;
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
    #if the device contains mmcblk, prefix is set to p
   #echo ${_OUTPUT_BLOCK_DEVICE} | grep -qs 'mmcblk' && { prefix="" || prefix='p'};
    
    #Set the proper name of the output block device's partitions
    #e.g /dev/sda1 /dev/sda2 etc.
    export _BLOCK_DEVICE_BOOT="${_OUTPUT_BLOCK_DEVICE}${prefix}1"
    export _BLOCK_DEVICE_ROOT="${_OUTPUT_BLOCK_DEVICE}${prefix}2"
}

# Image Preparation
prepare_image(){
    # shellcheck disable=SC2128
    echo_info "$FUNCNAME started at $(date)";
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
    mkdir -p "${_BUILD_DIR}"
    
    prepare_image_standard
    prepare_image_extra
    chroot_mkinitramfs
    chroot_umount || true
}

#run the standard commands for preparing the image
prepare_image_standard(){
    download_image
    extract_image
    copy_image
}
unmount_gracefully() {
    umount  "${_BUILD_DIR}/mount" || true
    umount  "${_BUILD_DIR}/boot" || true
    losetup -d "${loopdev}p1" || true
    losetup -d "${loopdev}p2" || true
    losetup -D || true
    rm -rf ${_BUILD_DIR}/mount || true
    rm -rf ${_BUILD_DIR}/boot || true
}

rollback()
{
    echo_error "Rolling back!"
    rm -rf "${_CHROOT_ROOT}" || true;
    unmount_gracefully
}

extract_image() {
    local image_name=$(basename ${_IMAGE_URL})
    local image="${_FILE_DIR}/${image_name}"
    local extracted_image="${_FILE_DIR}/extracted.img"

    if [ -e "$extracted_image" ]; then
        echo_info "$extracted_image found, skipping extract"
    else
        echo_info "Starting extract at $(date)"
        case ${image} in
            *.xz)
                echo_info "Extracting with xz"
                trap "rm -f $extracted_image; exit 1" ERR SIGINT
                pv ${image} | xz --decompress --stdout > "$extracted_image"
                trap - ERR SIGINT
                ;;
            *.zip)
                echo_info "Extracting with unzip"
                unzip -p $image > "$extracted_image"
                ;;
            *)
                echo_error "Unknown extension type on image: $IMAGE"
                exit 1
                ;;
        esac
        echo_info "Finished extract at $(date)"
    fi
}

copy_image(){
    trap "rollback" ERR SIGINT
    echo_debug "Mounting loopback";
    loopdev=$(losetup -P -f --show "$extracted_image");
    partprobe ${loopdev};
    mkdir "${_BUILD_DIR}/mount"
    mkdir "${_BUILD_DIR}/boot"
    mkdir "${_CHROOT_ROOT}"
    mount ${loopdev}p2 ${_BUILD_DIR}/mount
    mount ${loopdev}p1 ${_BUILD_DIR}/boot
    echo_info "Starting copy of boot to ${_CHROOT_ROOT}/boot at $(date)"
    rsync_local "${_BUILD_DIR}/boot" "${_CHROOT_ROOT}/"
    echo_info "Starting copy of mount to ${_CHROOT_ROOT} at $(date)"
    rsync_local "${_BUILD_DIR}/mount/"* "${_CHROOT_ROOT}"
    trap - ERR SIGINT
    unmount_gracefully
}
# Encrypt & Write SD
write_to_disk(){
    echo_info "$FUNCNAME started at $(date) "
    local continue
    echo_warn "CHECK DISK IS CORRECT"
    echo_info "$(lsblk)"
    echo_info ""
    read -p "Type 'YES' if the selected device is correct:  ${_OUTPUT_BLOCK_DEVICE}" continue
    if [ "${continue}" = 'YES' ] ; then
        stage2
    fi
}

stage2(){
  fs_type=$_FILESYSTEM_TYPE

  # TODO(kaligraffy) - variable duplication, needs sorting ideally
  export _CHROOT_ROOT=/mnt/cryptmypi
      
  echo_debug "Attempt to unmount just to be safe "
  umount ${_OUTPUT_BLOCK_DEVICE}* || true
  umount ${_CHROOT_ROOT} || {
      umount -l ${_CHROOT_ROOT} || true
      umount -f ${_ENCRYPTED_VOLUME_PATH} || true
  }

  [ -d ${_CHROOT_ROOT} ] && rm -r ${_CHROOT_ROOT} || true
  cryptsetup luksClose ${_ENCRYPTED_VOLUME_PATH} || true
  echo_debug "Partitioning SD Card"
  parted ${_OUTPUT_BLOCK_DEVICE} --script -- mklabel msdos
  parted ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary fat32 0 256
  parted ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary 256 -1
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
  echo_debug "Mounting ${_ENCRYPTED_VOLUME_PATH} to ${_CHROOT_ROOT}"
  mkdir ${_CHROOT_ROOT}
  mount ${_ENCRYPTED_VOLUME_PATH} ${_CHROOT_ROOT} && echo_debug "- Mounted ${_ENCRYPTED_VOLUME_PATH} to ${_CHROOT_ROOT}"

  # Mount boot partition
  echo_debug "Attempting to mount ${_BLOCK_DEVICE_BOOT} to ${_CHROOT_ROOT}/boot "
  mkdir ${_CHROOT_ROOT}/boot

  mount ${_BLOCK_DEVICE_BOOT} ${_CHROOT_ROOT}/boot && echo_debug "- Mounted ${_BLOCK_DEVICE_BOOT} to ${_CHROOT_ROOT}/boot"

  # Attempt to copy files from build to mounted device
  rsync_local "${_BUILD_DIR}/root" "${_CHROOT_ROOT}"
  chroot_mount
  chroot_mkinitramfs
  chroot_umount || true
  unmount_block_device ${_BLOCK_DEVICE_BOOT} || true
  unmount_block_device ${_BLOCK_DEVICE_ROOT} || true

  # Close LUKS
  cryptsetup -v luksClose "${_ENCRYPTED_VOLUME_PATH}" | echo_debug "Closing LUKS ${_BLOCK_DEVICE_ROOT}"

  # Clean up
  rm -r ${_CHROOT_ROOT}
  sync
}

chroot_mount(){
    echo_debug "Preparing chroot mount structure at '${_CHROOT_ROOT}'."
    # mount binds
    echo_debug "Mounting '${_CHROOT_ROOT}/dev/' "
    mount --bind /dev ${_CHROOT_ROOT}/dev/ || echo_error "mounting '${_CHROOT_ROOT}/dev/'"
    echo_debug "Mounting '${_CHROOT_ROOT}/dev/pts' "
    mount --bind /dev/pts ${_CHROOT_ROOT}/dev/pts || echo_error "mounting '${_CHROOT_ROOT}/dev/pts'"
    echo_debug "Mounting '${_CHROOT_ROOT}/sys/' ";
    mount --bind /sys ${_CHROOT_ROOT}/sys/ || echo_error "mounting '${_CHROOT_ROOT}/sys/'";
    echo_debug "Mounting '${_CHROOT_ROOT}/proc/' ";
    mount -t proc /proc ${_CHROOT_ROOT}/proc/ || echo_error "mounting '${_CHROOT_ROOT}/proc/'";
}

chroot_umount(){
    echo_debug "Unmounting binds"
    umount ${_CHROOT_ROOT}/dev/pts || true;
    umount ${_CHROOT_ROOT}/dev || true;
    umount ${_CHROOT_ROOT}/sys || true;
    umount ${_CHROOT_ROOT}/proc || true;
}

# Unmount boot partition
# arguments: a block device e.g. /dev/sda1
unmount_block_device(){
    echo_debug "Attempting to unmount ${1} "
    if umount ${1} ; then
        echo_debug "- Unmounted ${1}"
    else
        echo_error "- Aborting since we failed to unmount ${1}"
        exit 1
    fi
}

#run apt update
chroot_update(){
    #Force https on initial use of apt for the main kali repo
    sed -i 's|http:|https:|g' ${_CHROOT_ROOT}/etc/apt/sources.list;

    if [ ! -f "${_CHROOT_ROOT}/etc/resolv.conf" ]; then
        echo_warn "${_CHROOT_ROOT}/etc/resolv.conf does not exist";
        echo_warn "Setting nameserver to $_DNS1 and $_DNS2 in ${_CHROOT_ROOT}/etc/resolv.conf";
        echo -e "nameserver $_DNS1\nnameserver $_DNS2" > "${_CHROOT_ROOT}/etc/resolv.conf";
    fi

    echo_debug "Updating apt-get";
    chroot ${_CHROOT_ROOT} apt-get -qq update;
}

#installs packages from build
#arguments: a list of packages
chroot_package_install(){
    echo_info "- Installing $1";
    chroot_execute apt-get -qq -y install ${1} ;
}

#removes packages from build
#arguments: a list of packages
chroot_package_purge(){
    echo_info "- Purging $1";
    chroot_execute apt-get -qq -y purge ${1} ;
    chroot_execute apt-get -qq -y autoremove ;
}

chroot_execute(){
    chroot ${_CHROOT_ROOT} "$@";
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
    echo_debug "Building new initramfs (CHROOT is ${_CHROOT_ROOT})";

    #Point crypttab to the current physical device during mkinitramfs
    echo_debug "  Creating symbolic links from current physical device to crypttab device (if not using sd card mmcblk0p)";
    test -e "/dev/mmcblk0p1" || (test -e "${_BLOCK_DEVICE_BOOT}" && ln -s "${_BLOCK_DEVICE_BOOT}" "/dev/mmcblk0p1");
    test -e "/dev/mmcblk0p2" || (test -e "${_BLOCK_DEVICE_ROOT}" && ln -s "${_BLOCK_DEVICE_ROOT}" "/dev/mmcblk0p2");
    # determining the kernel
    kernel_version=$(ls ${_CHROOT_ROOT}/lib/modules/ | grep "${_KERNEL_VERSION_FILTER}" | tail -n 1);
    echo_debug "kernel is '${kernel_version}'";
    chroot_execute update-initramfs -u -k all;
    chroot_execute mkinitramfs -o /boot/initramfs.gz -v ${kernel_version};

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
    echo_info "Starting copy of $1 to $2 at $(date)"
    rsync \
        --hard-links \
        --archive \
        --verbose \
        --partial \
        --progress \
        --quiet \
        --info=progress2 "${1}" "${2}"
    echo_info "Finished copy of $1 to $2 at $(date)"
    sync;
}

#Download an image file to the file directory
download_image(){
    local image_name=$(basename ${_IMAGE_URL})
    mkdir -p "${_FILE_DIR}"
    local image_out_file=${_FILE_DIR}/${image_name}
    echo_info "Starting download at $(date)"
    wget -nc "${_IMAGE_URL}" -O "${image_out_file}" || true
    echo_info "Completed download at $(date)"
    echo_info "Checking image checksum"
    echo ${_IMAGE_SHA256}  $image_out_file | sha256sum --check --status
    echo_info "- valid"
}

# EXIT trap
trap_on_exit() {
    cleanup;
    echo_error "something went wrong. bye.";
}
trap "trap_on_exit" EXIT;
