#!/bin/bash
# shellcheck disable=SC2034
set -e
set -u

_COLOR_BLACK='\033[0;30m'
_COLOR_DARKGRAY='\033[1;30m'
_COLOR_RED='\033[0;31m'
_COLOR_LIGHTRED='\033[1;31m'
_COLOR_GREEN='\033[0;32m'
_COLOR_LIGHTGREEN='\033[1;32m'
_COLOR_ORANGE='\033[0;33m'
_COLOR_YELLOW='\033[1;33m'
_COLOR_BLUE='\033[0;34m'
_COLOR_LIGHTBLUE='\033[1;34m'
_COLOR_PURPLE='\033[0;35m'
_COLOR_LIGHTPURPLE='\033[1;35m'
_COLOR_CYAN='\033[0;36m'
_COLOR_LIGHTCYAN='\033[1;36m'
_COLOR_LIGHTGRAY='\033[0;37m'
_COLOR_WHITE='\033[1;37m'
_COLOR_NORMAL='\033[0m' # No Color

echo_error(){
    echo -e "${_COLOR_RED}$@${_COLOR_NORMAL}"
}

echo_warn(){
    echo -e "${_COLOR_YELLOW}$@${_COLOR_NORMAL}"
}

echo_info(){
    echo -e "${_COLOR_PURPLE}$@${_COLOR_NORMAL}"
}

echo_debug(){
    if [ $_LOG_LEVEL -lt 1 ]; then
        echo -e "${_COLOR_LIGHTGRAY}$@${_COLOR_NORMAL}"
    fi
}

# Message on exit
exitMessage(){
    if [ $1 -gt 0 ]; then
        echo_error "Script failed with exit status $1 at line $2"
    fi
    echo_info "Script completed at $(date)"
    
}

# Cleanup on exit
cleanup(){
    chroot_umount || true
    umount ${_BLKDEV}* || true
    umount -l /mnt/cryptmypi || true
        umount -f /dev/mapper/${_ENCRYPTED_VOLUME_NAME} || true
    [ -d /mnt/cryptmypi ] && rm -r /mnt/cryptmypi || true
    cryptsetup luksClose $_ENCRYPTED_VOLUME_NAME || true
}

trapExit () { exitMessage $1 $2 ; cleanup; }

myhooks(){
    _HOOKOP="${1}"
    for _HOOK in ${_BASEDIR}/hooks/????-${_HOOKOP}*
    do
        if [ -e ${_HOOK} ]; then
            echo_info "- Calling $(basename ${_HOOK}) "
            . ${_HOOK}
            echo_debug "- $(basename ${_HOOK}) completed"
        fi
    done
}

############################
# Validate All Preconditions
############################
stagePreconditions(){
    echo_info "$FUNCNAME started at $(date)"
    myhooks preconditions
}

############################
# STAGE 1 Image Preparation
############################
stage1(){
    echo_info "$FUNCNAME started at $(date) "
    mkdir -p "${_BUILDDIR}"
    myhooks stage1
    stage1-extra
    chroot_mkinitramfs
    chroot_umount || true
}

############################
# STAGE 2 Encrypt & Write SD
############################
stage2(){
    echo_info "$FUNCNAME started at $(date) "
    _PARTITIONPREFIX=""
    echo ${_BLKDEV} | grep -qs "mmcblk" && _PARTITIONPREFIX=p   
    
    # Show Stage2 menu
    local CONTINUE
    echo_warn "WARNING: CHECK DISK IS CORRECT"
    echo_info "$(lsblk)"
    read -p "Type 'YES' if the selected device is correct:  ${_BLKDEV}" CONTINUE
    if [ "${CONTINUE}" = 'YES' ] ; then
        myhooks stage2
    fi
}

chroot_mount(){
    echo_debug "Preparing chroot mount structure at '${_CHROOT_ROOT}'."
    # mount binds
    echo_debug "Mounting '${_CHROOT_ROOT}/dev/' "
    mount --bind /dev ${_CHROOT_ROOT}/dev/ || echo_error "ERROR while mounting '${_CHROOT_ROOT}/dev/'"
    echo_debug "Mounting '${_CHROOT_ROOT}/dev/pts' "
    mount --bind /dev/pts ${_CHROOT_ROOT}/dev/pts || echo_error "ERROR while mounting '${_CHROOT_ROOT}/dev/pts'"
    echo_debug "Mounting '${_CHROOT_ROOT}/sys/' "
    mount --bind /sys ${_CHROOT_ROOT}/sys/ || echo_error "ERROR while mounting '${_CHROOT_ROOT}/sys/'"
    echo_debug "Mounting '${_CHROOT_ROOT}/proc/' "
    mount -t proc /proc ${_CHROOT_ROOT}/proc/ || echo_error "ERROR while mounting '${_CHROOT_ROOT}/proc/'"
}

chroot_umount(){
    echo_debug "Unmounting binds"
    umount ${_CHROOT_ROOT}/dev/pts || true
    umount ${_CHROOT_ROOT}/dev || true
    umount ${_CHROOT_ROOT}/sys || true
    umount ${_CHROOT_ROOT}/proc || true
}

chroot_update(){
    #Force https on initial use of apt for the main kali repo
    sed -i 's|http:|https:|g' ${_CHROOT_ROOT}/etc/apt/sources.list
    
    if [ ! -f "${_CHROOT_ROOT}/etc/resolv.conf" ]; then
        echo_warn "${_CHROOT_ROOT}/etc/resolv.conf does not exists."
        echo_warn "Setting nameserver to $_DNS1 and $_DNS2 in ${_CHROOT_ROOT}/etc/resolv.conf"
        echo -e "nameserver $_DNS1\nnameserver $_DNS2" > "${_CHROOT_ROOT}/etc/resolv.conf"
    fi

    echo_debug "Updating apt-get"
    chroot ${_CHROOT_ROOT} apt-get update
}

chroot_pkginstall(){
    if [ -n "$1" ]; then
      for PACKAGE in "$@"; do
        echo_info "- Installing ${PACKAGE}"
        chroot ${_CHROOT_ROOT} apt-get -y install "${PACKAGE}" || {
            echo_error "ERROR: Could not install ${PACKAGE}"
        }
      done
    fi    
}  

chroot_pkgpurge(){
    if [ -n "$1" ]; then
      for PACKAGE in "$@"; do
        echo_info "- Uninstalling ${PACKAGE}"
        chroot ${_CHROOT_ROOT} apt-get -y purge "${PACKAGE}" || {
            echo_error "ERROR: Could not remove ${PACKAGE}"
        }
      done
    fi
    chroot ${_CHROOT_ROOT} apt-get -y autoremove
} 

chroot_execute(){
    chroot ${_CHROOT_ROOT} "$@"
}

chroot_mkinitramfs(){
    echo_debug "Building new initramfs (CHROOT is ${_CHROOT_ROOT})"

    #Point crypttab to the current physical device during mkinitramfs
    echo_debug "  Creating symbolic links from current physical device to crypttab device (if not using sd card mmcblk0p)"
    test -e "/dev/mmcblk0p1" || (test -e "${_BLKDEV}1" && ln -s "${_BLKDEV}1" "/dev/mmcblk0p1")
    test -e "/dev/mmcblk0p2" || (test -e "${_BLKDEV}2" && ln -s "${_BLKDEV}2" "/dev/mmcblk0p2")

    # determining the kernel
    _KERNEL_VERSION=$(ls ${_CHROOT_ROOT}/lib/modules/ | grep "${_KERNEL_VERSION_FILTER}" | tail -n 1)
    echo_debug "  Using kernel '${_KERNEL_VERSION}'"
    chroot_execute update-initramfs -u -k all
    # Finally, Create the initramfs
    echo_debug "  Building new initramfs "
    chroot_execute mkinitramfs -o /boot/initramfs.gz -v ${_KERNEL_VERSION}

    # cleanup
    echo_debug "  Cleaning up symbolic links"
    test -L "/dev/mmcblk0p1" && unlink "/dev/mmcblk0p1"
    test -L "/dev/mmcblk0p2" && unlink "/dev/mmcblk0p2"
}

assure_box_sshkey(){
    _KEYFILE="${_FILEDIR}/id_rsa"

    echo_debug "    Asserting box ssh keyfile:"
    test -f "${_KEYFILE}" && {
        echo_debug "    - Keyfile ${_KEYFILE} already exists"
    } || {
        echo_debug "    - Keyfile ${_KEYFILE} does not exists. Generating "
        ssh-keygen -q -t rsa -N '' -f "${_KEYFILE}" 2>/dev/null <<< y >/dev/null
        chmod 600 "${_KEYFILE}"
        chmod 644 "${_KEYFILE}.pub"
    }

    echo_debug "    - Copying keyfile ${_KEYFILE} to box's default user .ssh directory "
    cp "${_KEYFILE}" "${_CHROOT_ROOT}/.ssh/id_rsa"
    cp "${_KEYFILE}.pub" "${_CHROOT_ROOT}/.ssh/id_rsa.pub"
    chmod 600 "${_CHROOT_ROOT}/.ssh/id_rsa"
    chmod 644 "${_CHROOT_ROOT}/.ssh/id_rsa.pub"
}

backup_and_use_sshkey(){
    local _TMP_KEYPATH=$1
    local _TMP_KEYNAME=$(basename ${_TMP_KEYPATH})

    test -f "${_FILEDIR}/${_TMP_KEYNAME}" && {
        cp "${_FILEDIR}/${_TMP_KEYNAME}" "${_TMP_KEYPATH}"
        chmod 600 "${_TMP_KEYPATH}"
    } || {
        cp "${_TMP_KEYPATH}" "${_FILEDIR}/${_TMP_KEYNAME}"
    }
}
