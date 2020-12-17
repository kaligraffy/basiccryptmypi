#!/bin/bash
# shellcheck disable=SC2034
# Hold all configuration
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
    umount -l /mnt/cryptmypi || true
    umount -f ${_ENCRYPTED_VOLUME_PATH} || true
    [ -d /mnt/cryptmypi ] && rm -r /mnt/cryptmypi || true
    cryptsetup luksClose $_ENCRYPTED_VOLUME_NAME || true
}

call_hooks(){
    local hookop="${1}"
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
    echo ${_OUTPUT_BLOCK_DEVICE} | grep -qs 'mmcblk' && \
      prefix="" || prefix='p';
    
    #Set the proper name of the output block device's partitions
    #e.g /dev/sda1 /dev/sda2 etc.
    export _BLOCK_DEVICE_BOOT="${_OUTPUT_BLOCK_DEVICE}${prefix}1"
    export _BLOCK_DEVICE_ROOT="${_OUTPUT_BLOCK_DEVICE}${prefix}2"
}

# Image Preparation
prepare_image(){
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
    call_hooks stage1
    prepare_image_extra
    chroot_mkinitramfs
    chroot_umount || true
}

# Encrypt & Write SD
write_to_disk(){
    echo_info "$FUNCNAME started at $(date) "
    # TODO(kaligraffy) - don't like this here.
    # Changes _CHROOT_ROOT from build/root to /mnt/cryptmypi for stage 2
    export _CHROOT_ROOT=/mnt/cryptmypi
    local continue
    echo_warn "CHECK DISK IS CORRECT"
    echo_info "$(lsblk)"
    echo_info ""
    read -p "Type 'YES' if the selected device is correct:  ${_OUTPUT_BLOCK_DEVICE}" continue
    if [ "${continue}" = 'YES' ] ; then
        call_hooks stage2
    fi
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

# EXIT trap
trap_on_exit() {
    cleanup ;
    echo_error "something went wrong. bye.";
}
trap "trap_on_exit" EXIT;
