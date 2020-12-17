#!/bin/bash
set -e;
set -u;
# Get the base path for this script
export _BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";
export _USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6);
export _DNS1='1.1.1.1'
export _DNS2='8.8.8.8'
export _CPU_GOVERNOR='ondemand' #can be 'performance'
export _ROOTPASSWD='CHANGEME'
export _LUKSNUKEPASSWD='BOOM'
export _IODINE_DOMAIN=
export _LOCALE='en_US.UTF-8'
export _IODINE_PASSWORD=
export _OPENVPN_CONFIG_ZIP=
export _KERNEL_VERSION_FILTER="l+"
export _HOSTNAME="kali"
export _BLKDEV="/dev/sda"
export _FILESYSTEM_TYPE="btrfs"
export _LUKSCIPHER="aes-xts-plain64 --key-size 512 --use-random --hash sha512 \
                    --pbkdf argon2i --iter-time 5000"
export _PKGS_TO_PURGE=""
export _PKGS_TO_INSTALL="tree htop ufw timeshift"
export _LUKSPASSWD="CHANGEME"
export _IMAGE_SHA256="c6ceee472eb4dabf4ea895ef53c7bd28751feb44d46ce2fa3f51eb5469164c2c"
export _IMAGE_URL="https://images.kali.org/arm-images/kali-linux-2020.4-rpi4-nexmon-64.img.xz"
export _SSH_LOCAL_KEYFILE="$_USER_HOME/.ssh/id_rsa"
export _SSH_PASSWORD_AUTHENTICATION="no"
export _SSH_BLOCK_SIZE='4096'
export _SSH_KEY_PASSPHRASE="CHANGEME"
export _ENCRYPTED_VOLUME_NAME="crypt-1"
export _WIFI_SSID='WIFI'
export _WIFI_PASS='CHANGEME'
export _WIFI_INTERFACE='wlan0'
export _INITRAMFS_WIFI_IP=":::::${_WIFI_INTERFACE}:dhcp:${_DNS1}:${_DNS2}"
export _INITRAMFS_WIFI_DRIVERS='brcmfmac43455 brcmfmac brcmutil cfg80211 rfkill'
export _BUILDDIR=${_BASEDIR}/build
export _FILEDIR=${_BASEDIR}/build
export _CHROOT_ROOT=${_BUILDDIR}/root
#0 = debug messages and normal, 1 normal only
export _LOG_LEVEL=0
echo ${_BLKDEV} | grep -qs 'mmcblk' && export
_PARTITIONPREFIX="" ||  export _PARTITIONPREFIX='p';

#Optional and experimental hooks
prepare_image_extra(){
    call_hooks 0000-experimental-boot-hash.sh
    call_hooks 0000-optional-initramfs-luksnuke.sh
    call_hooks 0000-optional-sys-cpu-governor.sh
    call_hooks 0000-optional-sys-dns.sh
    call_hooks 0000-optional-sys-rootpassword.sh
    #call_hooks 0000-experimental-initramfs-wifi.sh
    #call_hooks 0000-experimental-sys-iodine.sh
    #call_hooks 0000-experimental-initramfs-iodine.sh
    #call_hooks 0000-optional-sys-docker.sh
    #call_hooks 0000-optional-sys-vpnclient.sh
    #call_hooks 0000-optional-sys-wifi.sh
}
