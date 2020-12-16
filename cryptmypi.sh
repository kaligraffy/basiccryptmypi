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
export _USER_HOME=$(eval echo ~${SUDO_USER})
export _DNS1='1.1.1.1'
export _DNS2='8.8.8.8'
export _CPU_GOVERNOR='performance'
export _WIFI_SSID='SKYNET'
export _WIFI_PASS='JOHNCONNOR'
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
export _PKGS_TO_INSTALL="" #tree htop ufw timeshift"
export _LUKSPASSWD=""
export _IMAGESHA="c6ceee472eb4dabf4ea895ef53c7bd28751feb44d46ce2fa3f51eb5469164c2c"
export _IMAGEURL="https://images.kali.org/arm-images/kali-linux-2020.4-rpi4-nexmon-64.img.xz"
export _SSH_LOCAL_KEYFILE="$_USER_HOME/.ssh/id_rsa"
export _SSH_PASSWORD_AUTHENTICATION="no"
export _ENCRYPTED_VOLUME_NAME="crypt-1"
export _BASEDIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export _CURRDIR=$(pwd)
export _CONFDIRNAME="${1%/}"
export _CONFDIR=${_CURRDIR}/${_CONFDIRNAME}
export _OTHER_SCRIPTS_DIR=${_CURRDIR}/other-scripts
export _BUILDDIR=${_CONFDIR}/build
export _CHROOT_ROOT=${_BUILDDIR}/root
export _FILESDIR=${_BASEDIR}/files
export _IMAGEDIR=${_FILESDIR}/images
#0 = debug messages and normal, 1 normal only
export _LOG_LEVEL=0
export _IMAGENAME=$(basename ${_IMAGEURL})

# Load Script Base Functions
. ${_BASEDIR}/functions.sh

# EXIT Trap
trapExit () { exitMessage $1 $2 ; cleanup; }
trap 'trapExit $? $LINENO' EXIT

############################
# Validate All Preconditions
############################
stagePreconditions(){
    echo_info "$FUNCNAME started at $(date)"

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
    
    myhooks preconditions
}
############################
# STAGE 1 Image Preparation
############################
stage1(){
    echo_info "$FUNCNAME started at `date` "
    myhooks stage1
}

############################
# STAGE 2 Encrypt & Write SD
############################
stage2(){
    echo_info "$FUNCNAME started at `date` "
    # Simple check for type of sdcard block device
    if [ echo ${_BLKDEV} | grep -qs "mmcblk" ]
    then
        __PARTITIONPREFIX=p
    else
        __PARTITIONPREFIX=""
    fi

    # Show Stage2 menu
    local CONTINUE
    echo_warn "${_BLKDEV} will not be overwritten."
    echo_warn "WARNING: CHECK DISK IS CORRECT"
    echo_info "$(lsblk)"
    echo_info "Type 'YES' if the selected device is correct:  ${_BLKDEV}"
    read CONTINUE
    if "${CONTINUE}" = 'YES' ] ; then
        myhooks stage2
    fi
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
        
        if [ "${CONTINUE}" = 'y' ] || [ "${CONTINUE}" = 'Y' ]; then
            echo_warn "Cleaning old build."
            rm -Rf ${_BUILDDIR}
        fi
        stage1
    fi
    
    myhooks 0000-experimental-boot-hash.sh
    #myhooks 0000-experimental-initramfs-iodine.sh
    myhooks 0000-experimental-initramfs-wifi.sh
    #myhooks 0000-experimental-sys-iodine.sh
    myhooks 0000-optional-initramfs-luksnuke.sh
    myhooks 0000-optional-sys-cpugovernor-ondemand.sh
    myhooks 0000-optional-sys-dns.sh
    #myhooks 0000-optional-sys-docker.sh
    myhooks 0000-optional-sys-rootpassword.sh
    #myhooks 0000-optional-sys-vpnclient.sh
    #myhooks 0000-optional-sys-wifi.sh
    
    stage2
    exit 0
}

main | tee ${_BUILDDIR}/build.log
