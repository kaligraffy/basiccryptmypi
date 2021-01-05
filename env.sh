#!/bin/bash
set -eu

export _NO_PROMPTS="1"; #1 or 0
export _LUKS_PASSWORD="CHANGEME"
export _ROOT_PASSWORD="CHANGEME"
export _KALI_PASSWORD="CHANGEME"
export _SSH_KEY_PASSPHRASE="CHANGEME"
export _WIFI_PASSWORD='CHANGEME'
export _LUKS_NUKE_PASSWORD="."
###############################################
export _DNS1='1.1.1.1'
export _DNS2='9.9.9.9'
###############################################
export _CPU_GOVERNOR="ondemand" #can be 'performance'
###############################################
export _IODINE_DOMAIN=
export _IODINE_PASSWORD=
###############################################
export _OPENVPN_CONFIG_ZIP=
###############################################
export _HOSTNAME="pikal"
export _KERNEL_VERSION_FILTER="l+"
export _LOCALE='en_US.UTF-8'
###############################################
export _OUTPUT_BLOCK_DEVICE="/dev/sda"
export _FILESYSTEM_TYPE="btrfs" #can also be ext4
###############################################
#0 = debug messages and normal, 1 normal only
export _LOG_LEVEL=1
###############################################
export _LUKS_CONFIGURATION="aes-xts-plain64 --key-size 512 --use-random --hash sha512 \
 --pbkdf argon2i --iter-time 5000"
###############################################
export _PKGS_TO_INSTALL=""
export _PKGS_TO_INSTALL="tree htop nethogs timeshift midori taskwarrior pass usbguard lynis debsecan debsums fail2ban firejail lynx"
#samhain apt-listbugs
export _PKGS_TO_PURGE=""
###############################################
export _IMAGE_SHA256="c6ceee472eb4dabf4ea895ef53c7bd28751feb44d46ce2fa3f51eb5469164c2c"
# Uncomment to skip check:
#export _IMAGE_SHA256=
export _IMAGE_URL="https://images.kali.org/arm-images/kali-linux-2020.4-rpi4-nexmon-64.img.xz"
###############################################
export _USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6);
export _SSH_LOCAL_KEYFILE="$_USER_HOME/.ssh/id_rsa"
export _SSH_PASSWORD_AUTHENTICATION="no"
export _SSH_BLOCK_SIZE='4096'
#SSH PORT used in dropbear setup, ufw setup optional scripts
export _SSH_PORT='2222'
###############################################
export _WIFI_SSID='WIFI'
export _WIFI_INTERFACE='wlan0'
###############################################
export _INITRAMFS_WIFI_IP=":::::${_WIFI_INTERFACE}:dhcp:${_DNS1}:${_DNS2}"
export _INITRAMFS_WIFI_DRIVERS='brcmfmac43455 brcmfmac brcmutil cfg80211 rfkill'
export _INITRAMFS_WIFI_INTERFACE='wlan0'
###############################################
#Optional and experimental hooks
extra_setup(){
#   iodine_setup
#   initramfs_wifi_setup
  hostname_setup;
  boot_hash_setup
  display_manager_setup
#   dropbear_setup
  luks_nuke_setup
#   ssh_setup #todo: sensible ssh default configuration
  cpu_governor_setup
  dns_setup #reconfigure for https/tls over dns
#   docker_setup
  root_password_setup
  user_password_setup
#   vpn_client_setup
#   wifi_setup
  firewall_setup
  clamav_setup
  fake_hwclock_setup
  aide_setup
# apparmor_setup - todo
# firejail_setup - todo
# sysctl_hardening_setup - todo
  packages_setup;
  apt_upgrade
}
