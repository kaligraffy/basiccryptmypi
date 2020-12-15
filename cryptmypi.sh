#!/bin/bash
set -e

#???
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SOURCE="$(readlink "$SOURCE")"
[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
#???

#echo $((16*1024*1024)) > /proc/sys/vm/dirty_background_bytes
#echo $((48*1024*1024)) > /proc/sys/vm/dirty_bytes
export _DNS1='1.1.1.1'
export _DNS2='8.8.8.8'
export _CPU_GOVERNOR='performance'
export _WIFI_SSID=''
export _WIFI_PASS=''
export _WIFI_INTERFACE='wlan0'
export _INITRAMFS_WIFI_IP=":::::${_INITRAMFS_WIFI_INTERFACE}:dhcp:${_DNS1}:${_DNS2}"
export _INITRAMFS_WIFI_DRIVERS='brcmfmac43455 brcmfmac brcmutil cfg80211 rfkill'
export _ROOTPASSWD="toor"
export _LUKSNUKEPASSWD="luks_nuke_password"
export _IODINE_DOMAIN=""
export _IODINE_PASSWORD=""
export _OPENVPN_CONFIG_ZIP="openvpn.zip"
export _KERNEL_VERSION_FILTER="l+"
export _HOSTNAME="kali"
export _BLKDEV="/dev/sda"
export _FILESYSTEM_TYPE="btrfs"
export _LUKSCIPHER="aes-xts-plain64 --key-size 512 --use-random --hash sha512 --pbkdf argon2i --iter-time 5000"
export _PKGS_TO_PURGE=""
export _PKGS_TO_INSTALL="tree htop ufw timeshift"
export _LUKSPASSWD=""
export _IMAGESHA="c6ceee472eb4dabf4ea895ef53c7bd28751feb44d46ce2fa3f51eb5469164c2c"
export _IMAGEURL="https://images.kali.org/arm-images/kali-linux-2020.4-rpi4-nexmon-64.img.xz"
export _SSH_LOCAL_KEYFILE="$_USER_HOME/.ssh/id_rsa"
export _SSH_PASSWORD_AUTHENTICATION="no"
export _ENCRYPTED_VOLUME_NAME="crypt-1"
#_STAGE1_OTHERSCRIPT='stage1-otherscript.sh'
#_STAGE2_OTHERSCRIPT='stage2-otherscript.sh'
stage1_hooks(){
    stage1profile_complete
}
stage1_optional_hooks(){
    myhooks "experimental-initramfs-wifi"
    myhooks "experimental-boot-hash"
    myhooks "optional-initramfs-luksnuke"
    myhooks "optional-sys-gpugovernor-ondemand"
    myhooks "optional-sys-dns"
    #myhooks "experimental-initramfs-iodine.hook"
    #myhooks "experimental-sys-iodine.hook"
    #myhooks "optional-sys-vpnclient.hook"
}
stage2_optional_hooks(){
    myhooks "optional-sys-rootpassword"
    #myhooks "optional-sys-wifi"
    #myhooks "optional-sys-docker.hook"
}
export _BASEDIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export _CURRDIR=$(pwd)
export _CONFDIRNAME="${1}"
export _CONFDIR=${_CURRDIR}/${_CONFDIRNAME}
export _USER_HOME=$(eval echo ~${SUDO_USER})
export _SHAREDCONFDIR=${_CURRDIR}/shared-config
export _BUILDDIR=${_CONFDIR}/build
export _FILESDIR=${_BASEDIR}/files
export _IMAGEDIR=${_FILESDIR}/images
#0 = debug messages, 1+ = info, no debug messages 2+ = warnings 3+ = only errors
export _LOG_LEVEL=1
export _IMAGENAME=$(basename ${_IMAGEURL})
# Default input variable values
_STAGE1_CONFIRM=true
_STAGE2_CONFIRM=true
_BLKDEV_OVERRIDE=""
_STAGE1_REBUILD=""
_RMBUILD_ONREBUILD=false

# Load Script Base Functions
for _FN in ${_BASEDIR}/functions/*.sh
do
    . ${_FN}
    echo_debug "- $(basename ${_FN}) loaded"
done

# Message on exit
exitMessage(){
    if [ $1 -gt 0 ]; then
        echo_error "Script failed at `date` with exit status $1 at line $2"
    else
        echo_info "Script completed at `date`"
    fi
}
# Cleanup on exit
cleanup(){
    chroot_umount || true
    umount ${_BLKDEV}* || true
    umount /mnt/cryptmypi || {
        umount -l /mnt/cryptmypi || true
        umount -f /dev/mapper/${_ENCRYPTED_VOLUME_NAME} || true
    }
    [ -d /mnt/cryptmypi ] && rm -r /mnt/cryptmypi || true
    cryptsetup luksClose $_ENCRYPTED_VOLUME_NAME || true
}

# EXIT Trap
trapExit () { exitMessage $1 $2 ; cleanup; }
trap 'trapExit $? $LINENO' EXIT

############################
# Validate All Preconditions
############################
stagePreconditions(){
    echo_info "$FUNCNAME started at `date` "

    # Creating Directories
    mkdir -p "${_IMAGEDIR}"
    mkdir -p "${_FILESDIR}"
    mkdir -p "${_BUILDDIR}"

    # Check if configuration name was provided
    if [  -z "$_CONFDIRNAME" ]; then
        echo_error "ERROR: Configuration directory was not supplied. "
        display_help
        exit 1
    fi

    # Check if configuration file is present
    if [ ! -f ${_CONFDIR}/cryptmypi.conf ]; then
        echo_error "ERROR: Cannot find ${_CONFDIR}/cryptmypi.conf"
        exit 1
    fi

    # Overriding _BLKDEV if _BLKDEV_OVERRIDE set
    [ -z "${_BLKDEV_OVERRIDE}" ] || _BLKDEV=${_BLKDEV_OVERRIDE}

    myhooks preconditions
}
############################
# STAGE 1 Image Preparation
############################
stage1(){
    echo_info "$FUNCNAME started at `date` "
    function_exists "stage1_hooks" && {
        function_summary stage1_hooks
        stage1_hooks
    }
}

############################
# STAGE 2 Encrypt & Write SD
############################
stage2(){
    echo_info "$FUNCNAME started at `date` "
    # Simple check for type of sdcard block device
    if echo ${_BLKDEV} | grep -qs "mmcblk"
    then
        __PARTITIONPREFIX=p
    else
        __PARTITIONPREFIX=""
    fi

    # Show Stage2 menu
    local _CONTINUE
    $_STAGE2_CONFIRM && {

    echo_warn "Cryptmypi will now write the build to disk."
    echo_warn "WARNING: CHECK DISK IS CORRECT"
    echo_info "$(lsblk)"
    echo_info "Type 'YES' if the selected device is correct:  ${_BLKDEV}"
    echo -n ": "
        read _CONTINUE
    } || {
        echo_debug "STAGE2 confirmation set to FALSE: skipping confirmation"
        echo_debug "STAGE2 will execute (assuming 'YES' input) ..."
        _CONTINUE='YES'
    }

    case "${_CONTINUE}" in
        'YES')
            function_exists "stage2_hooks" && {
                function_summary stage2_hooks
                stage2_hooks
            } || myhooks "stage2"
            ;;
        *)
            echo "Abort."
            exit 1
            ;;
    esac
}

# Main logic routine
main(){
    stagePreconditions
    cd ${_BUILDDIR}
    echo_info "Starting Cryptmypi at $(date)"
    if [ ! -d ${_BUILDDIR} ]; then
        stage1
    else
        echo_debug "Build directory already exists: ${_BUILDDIR}"
        local CONTINUE
        echo_info "Rebuild? (y/N)"
        read _CONTINUE
        CONTINUE=$(echo "${CONTINUE}" | sed -e 's/\(.*\)/\L\1/')
        
        if ["${CONTINUE}" = 'y'] || [ "${CONTINUE}" = 'Y' ]; then
            echo_warn "Cleaning old build."
            rm -Rf ${_BUILDDIR}
        fi
        stage1
    fi
    stage2
    exit 0
}
main

