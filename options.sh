#!/bin/bash
# shellcheck disable=SC2034
# shellcheck disable=SC2145
# shellcheck disable=SC2086
# shellcheck disable=SC2068
# shellcheck disable=SC2128
set -eu
export _UFW_SETUP=0;

#sets the locale (e.g. en_US, en_UK)
locale_setup(){
  echo_info "$FUNCNAME";
  echo_debug "Uncommenting locale ${_LOCALE} for inclusion in generation"
  sed -i 's/^# *\(en_US.UTF-8\)/\1/' "${_CHROOT_ROOT}/etc/locale.gen";

  echo_debug "Updating /etc/default/locale";
  atomic_append "LANG=${_LOCALE}" "${_CHROOT_ROOT}/etc/default/locale";

  chroot_package_install "${_CHROOT_ROOT}" locales
  
  echo_debug "Updating env variables";
  chroot "${_CHROOT_ROOT}" /bin/bash -x <<- EOT
export LANG="${_LOCALE}"
export LANGUAGE="${_LOCALE}"
EOT

  atomic_append "export LANG=${_LOCALE}" "${_CHROOT_ROOT}/.bashrc"
  atomic_append "export LANGUAGE=${_LOCALE}"  "${_CHROOT_ROOT}/.bashrc"

  echo_debug "Generating locale"
  chroot_execute "${_CHROOT_ROOT}" locale-gen
}

#create wifi connection to a router/hotspot on boot
initramfs_wifi_setup(){
# REFERENCE:
#    http://www.marcfargas.com/posts/enable-wireless-debian-initramfs/
#    https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlock_via_wifi
#    http://retinal.dehy.de/docs/doku.php?id=technotes:raspberryrootnfs
  echo_info "$FUNCNAME";

  echo_debug "Attempting to set initramfs WIFI up "
  if [ -z "$_WIFI_SSID" ] || [ -z "$_WIFI_PASSWORD" ]; then
    echo_warn 'SKIPPING: _WIFI_PASSWORD and/or _WIFI_SSID are not set.'
    exit 1;
  fi

  # Checking if WIFI interface was provided
  if [ -z "${_INITRAMFS_WIFI_INTERFACE}" ]; then
    _INITRAMFS_WIFI_INTERFACE='wlan0'
    echo_warn "_INITRAMFS_WIFI_INTERFACE is not set on config: Setting default value ${_INITRAMFS_WIFI_INTERFACE}"
  fi

  # Checking if WIFI ip kernal param was provided
  if [ -z "${_INITRAMFS_WIFI_IP}" ]; then
    _INITRAMFS_WIFI_IP=":::::${_INITRAMFS_WIFI_INTERFACE}:dhcp:${_DNS1}:${_DNS2}"
    echo_warn "_INITRAMFS_WIFI_IP is not set on config: Setting default value ${_INITRAMFS_WIFI_IP}"
  fi

  # Checking if WIFI drivers param was provided
  if [ -z "${_INITRAMFS_WIFI_DRIVERS}" ]; then
    _INITRAMFS_WIFI_DRIVERS="brcmfmac brcmutil cfg80211 rfkill"
    echo_warn "_INITRAMFS_WIFI_DRIVERS is not set on config: Setting default value ${_INITRAMFS_WIFI_DRIVERS}"
  fi

  # Update /boot/cmdline.txt to boot crypt
  sed -i "s#rootwait#ip=${_INITRAMFS_WIFI_IP} rootwait#g" ${_CHROOT_ROOT}/boot/cmdline.txt

  echo_debug "Generating PSK for '${_WIFI_SSID}' '${_WIFI_PASSWORD}'";
  _WIFI_PSK=$(wpa_passphrase "${_WIFI_SSID}" "${_WIFI_PASSWORD}" | grep "psk=" | grep -v "#psk")

  echo_debug "Copying scripts";
  cp -p "${_FILE_DIR}/initramfs-scripts/zz-brcm" "${_CHROOT_ROOT}/etc/initramfs-tools/hooks/"
  cp -p "${_FILE_DIR}/initramfs-scripts/a_enable_wireless" "${_CHROOT_ROOT}/etc/initramfs-tools/scripts/init-premount/";
  cp -p "${_FILE_DIR}/initramfs-scripts/enable_wireless" "${_CHROOT_ROOT}/etc/initramfs-tools/hooks/"
  cp -p "${_FILE_DIR}/initramfs-scripts/kill_wireless" "${_CHROOT_ROOT}/etc/initramfs-tools/scripts/local-bottom/"
  
  sed -i "#_WIFI_INTERFACE#${_WIFI_INTERFACE}#" "${_CHROOT_ROOT}/etc/initramfs-tools/scripts/init-premount/a_enable_wireless";
  sed -i "#_INITRAMFS_WIFI_DRIVERS#${_INITRAMFS_WIFI_DRIVERS}#" "${_CHROOT_ROOT}/etc/initramfs-tools/hooks/enable_wireless";
 
  echo_debug "Creating wpa_supplicant file";
  cat <<- EOT > ${_CHROOT_ROOT}/etc/initramfs-tools/wpa_supplicant.conf
ctrl_interface=/tmp/wpa_supplicant
network={
 ssid="${_WIFI_SSID}"
 psk="${_WIFI_PSK}"
 scan_ssid=1
 key_mgmt=WPA-PSK
}
EOT

  # Adding modules to initramfs modules
  for driver in ${_INITRAMFS_WIFI_DRIVERS}; do
    atomic_append "${driver}" "${_CHROOT_ROOT}/etc/initramfs-tools/modules"
  done
  echo_debug "initramfs wifi completed";
}

#configure system on decrypt to connect to a hotspot specified in env file
wifi_setup(){
  echo_info "$FUNCNAME";

  # Checking if WIFI interface was provided
  if [ -z "${_WIFI_INTERFACE}" ]; then
    _WIFI_INTERFACE='wlan0'
    echo_warn "_WIFI_INTERFACE is not set on config: Setting default value ${_WIFI_INTERFACE}"
  fi

  echo_debug "Generating PSK for '${_WIFI_SSID}' '${_WIFI_PASSWORD}'"
  _WIFI_PSK=$(wpa_passphrase "${_WIFI_SSID}" "${_WIFI_PASSWORD}" | grep "psk=" | grep -v "#psk")

  echo_debug "Creating wpa_supplicant file"
  cat <<- EOT > ${_CHROOT_ROOT}/etc/wpa_supplicant.conf
ctrl_interface=/var/run/wpa_supplicant
network={
 ssid="${_WIFI_SSID}"
 scan_ssid=1
 proto=WPA RSN
 key_mgmt=WPA-PSK
 pairwise=CCMP TKIP
 group=CCMP TKIP
 ${_WIFI_PSK}
}
EOT

  echo_debug "Updating /etc/network/interfaces file"
  if [ ! $(grep -w "# The wifi interface" "${_CHROOT_ROOT}/etc/network/interfaces") ]; then
    cat <<- EOT >> "${_CHROOT_ROOT}/etc/network/interfaces"
# The wifi interface
auto ${_WIFI_INTERFACE}
allow-hotplug ${_WIFI_INTERFACE}
iface ${_WIFI_INTERFACE} inet dhcp
wpa-conf /etc/wpa_supplicant.conf
# pre-up wpa_supplicant -B -Dwext -i${_WIFI_INTERFACE} -c/etc/wpa_supplicant.conf
# post-down killall -q wpa_supplicant
EOT
  fi
  
  echo_debug "Create connection script /usr/local/bin/sys-wifi-connect.sh"
  cp -p "${_FILE_DIR}/wifi-scripts/sys-wifi-connect.sh" "${_CHROOT_ROOT}/usr/local/bin/sys-wifi-connect.sh"
  sed -i "s|_WIFI_INTERFACE|${_WIFI_INTERFACE}|" "${_CHROOT_ROOT}/usr/local/bin/sys-wifi-connect.sh";
  echo_debug "Add to cron to start at boot (before login)"
  echo "@reboot root /bin/sh /usr/local/bin/sys-wifi-connect.sh" > "${_CHROOT_ROOT}/etc/cron.d/sys-wifi"
  chmod 755 "${_CHROOT_ROOT}/etc/cron.d/sys-wifi";

}

#disable the gui 
display_manager_setup(){
  echo_info "$FUNCNAME";
  chroot_execute "$_CHROOT_ROOT" systemctl set-default multi-user
  echo_warn "To get a gui run startxfce4 on command line"
}

#setup dropbear in initramfs
dropbear_setup(){
  echo_info "$FUNCNAME";
  if [ ! -f "${_SSH_LOCAL_KEYFILE}" ]; then
      echo_error "ERROR: Obligatory SSH keyfile '${_SSH_LOCAL_KEYFILE}' could not be found. Exiting";
      exit 1;
  fi

  # Installing packages
  chroot_package_install "$_CHROOT_ROOT" dropbear dropbear-initramfs cryptsetup-initramfs

  atomic_append "DROPBEAR_OPTIONS='-p $_SSH_PORT -RFEjk -c /bin/cryptroot-unlock'" "${_CHROOT_ROOT}/etc/dropbear-initramfs/config";

  # Now append our key to dropbear authorized_keys file
  #TODO NONATOMIC fix when testing headless setup
  cat "${_SSH_LOCAL_KEYFILE}.pub" >> "${_CHROOT_ROOT}/etc/dropbear-initramfs/authorized_keys";
  chmod 600 ${_CHROOT_ROOT}/etc/dropbear-initramfs/authorized_keys;

  # Update dropbear for some sleep in initramfs
  sed -i 's#run_dropbear \&#sleep 5\nrun_dropbear \&#g' ${_CHROOT_ROOT}/usr/share/initramfs-tools/scripts/init-premount/dropbear;

  # Using provided dropbear keys (or backuping generating ones for later usage)
  # Don't use weak key ciphers
  rm ${_CHROOT_ROOT}/etc/dropbear-initramfs/dropbear_dss_host_key;
  rm ${_CHROOT_ROOT}/etc/dropbear-initramfs/dropbear_ecdsa_host_key;
  backup_dropbear_key "${_CHROOT_ROOT}/etc/dropbear-initramfs/dropbear_rsa_host_key";
}

luks_nuke_setup(){
  echo_info "$FUNCNAME";

# Install and configure cryptsetup nuke package if we were given a password
  if [ -n "${_LUKS_NUKE_PASSWORD}" ]; then
    echo_debug "Attempting to install and configure encrypted pi cryptsetup nuke password."
    chroot_package_install "${_CHROOT_ROOT}" cryptsetup-nuke-password
    chroot ${_CHROOT_ROOT} /bin/bash -c "debconf-set-selections <<- EOT
cryptsetup-nuke-password cryptsetup-nuke-password/password string ${_LUKS_NUKE_PASSWORD}
cryptsetup-nuke-password cryptsetup-nuke-password/password-again string ${_LUKS_NUKE_PASSWORD}
EOT
"
  chroot_execute "$_CHROOT_ROOT" dpkg-reconfigure -f noninteractive cryptsetup-nuke-password
  else
      echo_warn "Nuke password _LUKS_NUKE_PASSWORD not set. Skipping."
  fi
}

#TODO sensible ssh default configuration
ssh_setup(){
  echo_info "$FUNCNAME";

  sshd_config="${_CHROOT_ROOT}/etc/ssh/sshd_config"
  ssh_authorized_keys="${_CHROOT_ROOT}/.ssh/authorized_keys"

  if [ ! -f "${_SSH_LOCAL_KEYFILE}" ]; then
      echo_error "SSH keyfile '${_SSH_LOCAL_KEYFILE}' could not be found"
      exit 1;
  fi

  # Append our key to the default user's authorized_keys file
  echo_debug "Creating authorized_keys file"
  mkdir -p "${_CHROOT_ROOT}/.ssh/"
  cat "${_SSH_LOCAL_KEYFILE}.pub" > "${ssh_authorized_keys}"
  chmod 600 "${ssh_authorized_keys}"

  # Creating box's default user own key
  create_ssh_key;

  # Update sshd settings
  cp -p "${sshd_config}" "${sshd_config}.bak"
  if [ ! $( grep -w "#New SSH Config" "${sshd_config}") ]; then
  cat <<- EOT >> "${sshd_config}"
#New SSH Config
PasswordAuthentication $(echo $_SSH_PASSWORD_AUTHENTICATION)
Port $(echo $_SSH_PORT)
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
EOT
  fi
  
  #OPENS UP YOUR SSH PORT
  if (( $_UFW_SETUP == 1 )) ; then
    chroot_execute "$_CHROOT_ROOT" ufw allow in "${_SSH_PORT}/tcp";
    chroot_execute "$_CHROOT_ROOT" ufw enable;
  fi
}

#sets cpu performance mode (useful for running off battery)
cpu_governor_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "${_CHROOT_ROOT}" cpufrequtils;
  echo_warn "Use cpufreq-info/systemctl status cpufrequtils to confirm the changes when the device is running";
  echo "GOVERNOR=${_CPU_GOVERNOR}" | tee ${_CHROOT_ROOT}/etc/default/cpufrequtils;
  chroot_execute "$_CHROOT_ROOT" systemctl enable cpufrequtils;
}

#custom hostname setup
hostname_setup(){
  echo_info "$FUNCNAME";
  # Overwrites /etc/hostname
  echo "${_HOSTNAME}" > "${_CHROOT_ROOT}/etc/hostname";
  # Updates /etc/hosts
  sed -i "s#^127.0.0.1       kali#127.0.0.1  ${_HOSTNAME}#" "${_CHROOT_ROOT}/etc/hosts";
}

#sets the root password
root_password_setup(){
  echo_info "$FUNCNAME";
  chroot ${_CHROOT_ROOT} /bin/bash -c "echo root:${_ROOT_PASSWORD} | /usr/sbin/chpasswd"
}

#sets the kali user password
user_password_setup(){
  echo_info "$FUNCNAME";
  chroot ${_CHROOT_ROOT} /bin/bash -c "echo kali:${_KALI_PASSWORD} | /usr/sbin/chpasswd"
}

#setup a vpn client
vpn_client_setup(){
  echo_info "$FUNCNAME";

  _OPENVPN_CONFIG_ZIPFILE=${_OPENVPN_CONFIG_ZIP}
  _OPENVPN_CONFIG_ZIPPATH="${_FILE_DIR}/${_OPENVPN_CONFIG_ZIPFILE}"

  echo_debug "Assuring openvpn installation and config dir"
  chroot_package_install "$_CHROOT_ROOT" openvpn
  mkdir -p ${_CHROOT_ROOT}/etc/openvpn

  echo_debug "Unzipping provided files into configuration dir"
  unzip ${_OPENVPN_CONFIG_ZIPPATH} -d ${_CHROOT_ROOT}/etc/openvpn/

  echo_debug "Setting AUTOSTART to ALL on OPENVPN config"
  sed -i '/^AUTOSTART=/s/^/#/' ${_CHROOT_ROOT}/etc/default/openvpn
  sed -i '/^#AUTOSTART="all"/s/^#//' ${_CHROOT_ROOT}/etc/default/openvpn

  echo_debug "Enabling service "
  chroot_execute "$_CHROOT_ROOT" systemctl enable openvpn@client.service
}


#installs clamav and update/scanning daemons, updates to most recent definitions
clamav_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" clamav clamav-daemon
  chroot_execute "$_CHROOT_ROOT" systemctl enable clamav-freshclam.service
  chroot_execute "$_CHROOT_ROOT" systemctl enable clamav-daemon.service
  chroot_execute "$_CHROOT_ROOT" freshclam
  echo_debug "clamav installed"
}

#simulates a hardware clock
fake_hwclock_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" fake-hwclock
  # set clock even if saved value appears to be in the past
  # sed -i "s|^#FORCE=force|FORCE=force|"  "$_CHROOT_ROOT/etc/default/fake-hwclock"
  chroot_execute "$_CHROOT_ROOT" systemctl enable fake-hwclock
}

#update system
apt_upgrade(){
  echo_info "$FUNCNAME";
  chroot_execute "$_CHROOT_ROOT" apt -qq -y update
  chroot_execute "$_CHROOT_ROOT" apt -qq -y upgrade
}

#install and configure docker
#TODO Test docker
docker_setup(){
# REFERENCES
#   https://www.docker.com/blog/happy-pi-day-docker-raspberry-pi/
#   https://github.com/docker/docker.github.io/blob/595616145a53d68fb5be1d603e97666cefcb5293/install/linux/docker-ce/debian.md
#   https://docs.docker.com/engine/install/debian/
#   https://gist.github.com/decidedlygray/1288c0265457e5f2426d4c3b768dfcef
  echo_info "$FUNCNAME";
  echo_warn "Docker may conflict with VPN services/connections"
#   echo_debug "    Updating iptables  (issue: default kali iptables was stalling)"
#   systemctl start and stop commands would hang/stall due to pristine iptables on kali-linux-2020.1a-rpi3-nexmon-64.img.xz
#   chroot_package_install "$_CHROOT_ROOT" iptables
#   chroot_execute "$_CHROOT_ROOT" update-alternatives --set iptables /usr/sbin/iptables-legacy
#   chroot_execute "$_CHROOT_ROOT" update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Needed to avoid "cgroups: memory cgroup not supported on this system"
#   see https://github.com/moby/moby/issues/35587
#       cgroup_enable works on kernel 4.9 upwards
#       cgroup_memory will be dropped in 4.14, but works on < 4.9
#       keeping both for now
  sed -i "s#rootwait#cgroup_enable=memory cgroup_memory=1 rootwait#g" ${_CHROOT_ROOT}/boot/cmdline.txt
  chroot_package_install "$_CHROOT_ROOT" docker.io
  chroot_execute "$_CHROOT_ROOT" systemctl enable docker
  echo_debug "docker installed";
}

#install and remove custom packages
packages_setup(){
  echo_info "$FUNCNAME";
  chroot_package_purge "$_CHROOT_ROOT" "${_PKGS_TO_PURGE}";
  chroot_package_install "$_CHROOT_ROOT" "${_PKGS_TO_INSTALL}";
}

#sets up aide to run at midnight each night
aide_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "${_DISK_CHROOT_ROOT}" aide
  chroot_execute "${_DISK_CHROOT_ROOT}" aideinit
  chroot_execute "${_DISK_CHROOT_ROOT}" mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

  echo "0 0 * * * root /usr/sbin/aide --check --config=/etc/aide/aide.conf" > "${_CHROOT_ROOT}/etc/cron.d/aideCheck"
  chmod 755 "${_CHROOT_ROOT}/etc/cron.d/aideCheck";
}

#basic snapper install for use with btrfs, snapshots root directory in its entirety with default settings,
#snapper-gui errors
snapper_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "${_DISK_CHROOT_ROOT}" snapper 
  #chroot_execute "${_DISK_CHROOT_ROOT}" snapper create-config /
  #TODO Set sensible snapper configs for a limited space ssd
  echo_warn "Remember to set a reasonable snapper config";
}

#secure network time protocol configuration, also installs ntpdate client for manually pulling the time
ntpsec_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "${_CHROOT_ROOT}" ntpsec ntpsec-doc ntpsec-ntpdate
  chroot_execute "$_CHROOT_ROOT" systemctl enable ntpsec.service
  sed -i "s|^# server time.cloudflare.com nts|server time.cloudflare.com:123 iburst nts \nserver nts.sth1.ntp.se:123 iburst nts\nserver nts.sth2.ntp.se:123 iburst nts|" "/etc/ntpsec/ntp.conf" "${_CHROOT_ROOT}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 0.debian.pool.ntp.org iburst|#pool 0.debian.pool.ntp.org iburst|" "${_CHROOT_ROOT}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 1.debian.pool.ntp.org iburst|#pool 1.debian.pool.ntp.org iburst|" "${_CHROOT_ROOT}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 2.debian.pool.ntp.org iburst|#pool 2.debian.pool.ntp.org iburst|" "${_CHROOT_ROOT}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 3.debian.pool.ntp.org iburst|#pool 3.debian.pool.ntp.org iburst|" "${_CHROOT_ROOT}/etc/ntpsec/ntp.conf"
  chroot_execute "$_CHROOT_ROOT" mkdir /var/log/ntpsec
  chroot_execute "$_CHROOT_ROOT" chown ntpsec:ntpsec /var/log/ntpsec

  if (( $_UFW_SETUP == 1 )) ; then
    chroot_execute "$_CHROOT_ROOT" ufw allow out 123/tcp;
    chroot_execute "$_CHROOT_ROOT" ufw enable;
  fi
}

#config iodine
iodine_setup(){
  # REFERENCE:
  #   https://davidhamann.de/2019/05/12/tunnel-traffic-over-dns-ssh/
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" iodine

  # Create initramfs hook file for iodine
  cp -p "${_FILE_DIR}/initramfs-scripts/zz-iodine" "${_CHROOT_ROOT}/etc/initramfs-tools/hooks/"

  # Replace variables in iodine hook file
  sed -i "s#IODINE_PASSWORD#${_IODINE_PASSWORD}#g" "${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-iodine"
  sed -i "s#IODINE_DOMAIN#${_IODINE_DOMAIN}#g" "${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-iodine"

  # Create initramfs script file for iodine
  cp -p "${_FILE_DIR}/initramfs-scripts/iodine" "${_CHROOT_ROOT}/etc/initramfs-tools/scripts/init-premount/";
  echo_debug "iodine setup complete";
}

#vlc_setup, fix broken audio
vlc_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" vlc
  #stuttery audio fix on rpi4
  sed -i "s|load-module module-udev-detect|load-module module-udev-detect tsched=0|" "${_CHROOT_ROOT}/etc/pulse/default.pa"
  #TODO stuttery video fix on rpi4
}

#firejail setup
firejail_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" firejail firejail-profiles firetools
  chroot_execute "$_CHROOT_ROOT" firecfg
  #TODO firejail configuration for hardened malloc, apparmor integration
}

#TODO write sysctl.conf hardening here
sysctl_hardening_setup(){
  echo_info "$FUNCNAME";
  echo_warn "NOT YET IMPLEMENTED";
}

#make boot mount read only
mount_boot_readonly_setup(){
  echo_info "$FUNCNAME";
  sed -i "s#/boot           vfat    defaults          0       2#/boot           vfat    defaults,noatime,ro,errors=remount-ro          0       2#" "${_DISK_CHROOT_ROOT}/etc/fstab";
  echo_warn "Remember to remount when running mkinitramfs!";
} 

#automatically log you in after unlocking your encrypted drive, without a password...somehow. GUI only.
passwordless_login_setup(){
  echo_info "$FUNCNAME";
  sed -i "s|^#greeter-hide-users=false|greeter-hide-users=false|" "${_CHROOT_ROOT}/etc/lightdm/lightdm.conf"
  sed -i "s|^#autologin-user=$|autologin-user=${_PASSWORDLESS_LOGIN_USER}|" "${_CHROOT_ROOT}/etc/lightdm/lightdm.conf"
  sed -i "s|^#autologin-user-timeout=0|autologin-user-timeout=0|" "${_CHROOT_ROOT}/etc/lightdm/lightdm.conf"
}

#set default shell to a shell of your choice
default_shell_setup(){
  echo_info "$FUNCNAME";
  local main_user='kali'
  sed -i "s#root:x:0:0:root:/root:/usr/bin/bash#root:x:0:0:root:/root:/usr/bin/$_SHELL#" "${_CHROOT_ROOT}/etc/passwd";
  sed -i "s#$main_user:x:1000:1000::/home/$main_user:/usr/bin/bash#$main_user:x:1000:1000::/home/kali:/usr/bin/$_SHELL#" "${_CHROOT_ROOT}/etc/passwd";
  sed -i "s#$main_user:x:1000:1000::/home/$main_user:/usr/bin/zsh#$main_user:x:1000:1000::/home/kali:/usr/bin/$_SHELL#" "${_CHROOT_ROOT}/etc/passwd";
}

#enable bluetooth
bluetooth_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" bluez
  chroot_execute "$_CHROOT_ROOT" systemctl enable bluetooth               
  #TODO setup some bluetooth devices you might have already
}

#TODO Finish apparmor setup method off
# Installs apparmor
apparmor_setup(){
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" apparmor apparmor-profiles-extra apparmor-utils
  echo_warn "PACKAGES INSTALLED, NO KERNEL PARAMS CONFIGURED. PLEASE CONFIGURE MANUALLY";
}

#randomize mac on reboot
random_mac_on_reboot_setup(){
#https://wiki.archlinux.org/index.php/MAC_address_spoofing#Automatically
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" macchanger 
  cp -p "${_FILE_DIR}/random-mac-scripts/macspoof" "${_CHROOT_ROOT}/etc/systemd/system/macspoof@${_WIFI_INTERFACE}.service";
  chroot_execute "$_CHROOT_ROOT" systemctl enable macspoof@${_WIFI_INTERFACE}
}

#configures two ipv4 ip addresses as your global dns
#enables dnssec and DNSOverTLS
#disables mdns, llmnr
#credits: https://andrea.corbellini.name/2020/04/28/ubuntu-global-dns/
dns_setup(){
  echo_info "$FUNCNAME";
  chroot_execute "$_DISK_CHROOT_ROOT" systemctl disable resolvconf                                                                                                            
  chroot_execute "$_DISK_CHROOT_ROOT" systemctl enable systemd-resolved
  sed -i "s|^#DNS=|DNS=${_DNS1}|" "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf";
  sed -i "s|^#FallbackDNS=|FallbackDNS=${_DNS2}|" "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf";
  sed -i "s|^#DNSSEC=no|DNSSEC=true|" "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf";
  sed -i "s|^#DNSOverTLS=no|DNSOverTLS=yes|" "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf";
  sed -i "s|^#MulticastDNS=yes|MulticastDNS=no|" "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf";
  sed -i "s|^#LLMNR=yes|LLMNR=no|" "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf";
  
  cat <<- EOT > ${_DISK_CHROOT_ROOT}/etc/NetworkManager/conf.d/dns.conf
[main]
dns=none
systemd-resolved=false
[connection]
llmnr=no
mdns=no
EOT

  #add resolved dns to top of /etc/systemd/resolved.conf for use with NetworkManager:
  echo -e "nameserver 127.0.0.53\n$(cat "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf")" > "${_DISK_CHROOT_ROOT}/etc/systemd/resolved.conf"

  echo_debug "creating symlink";
  mv "${_DISK_CHROOT_ROOT}/etc/resolv.conf" "${_DISK_CHROOT_ROOT}/etc/resolv.conf.backup";
  chroot_execute "${_DISK_CHROOT_ROOT}" ln -s "/etc/systemd/resolved.conf" "/etc/resolv.conf";
  echo_debug "DNS configured - remember to keep your clock up to date (date -s XX:XX) or DNSSEC Certificate errors may occur";
  if (( $_UFW_SETUP == 1 )); then
    chroot_execute "${_DISK_CHROOT_ROOT}" ufw allow out 853/tcp;
    chroot_execute "${_DISK_CHROOT_ROOT}" ufw enable;
  fi
  #needs: 853/tcp, doesn't need as we disable llmnr and mdns: 5353/udp,5355/udp
}

#installs a basic firewall
#TODO fix ufw logging so it doesn't log to syslog
#TODO replace with a new nftables script for more granular control
#this must be called before ssh_setup, dns_setup, ntpsec_setup or the script 
#will not work correctly
firewall_setup(){
  echo_info "$FUNCNAME";

  # Installing packages
  chroot_package_install "$_CHROOT_ROOT" ufw;
  chroot_execute "$_CHROOT_ROOT" ufw logging high;
  chroot_execute "$_CHROOT_ROOT" ufw default deny outgoing;
  chroot_execute "$_CHROOT_ROOT" ufw default deny incoming;
  chroot_execute "$_CHROOT_ROOT" ufw default deny routed;
  
  chroot_execute "$_CHROOT_ROOT" ufw allow out 53/udp;
  chroot_execute "$_CHROOT_ROOT" ufw allow out 80/tcp;
  chroot_execute "$_CHROOT_ROOT" ufw allow out 443/tcp;
  
  chroot_execute "$_CHROOT_ROOT" ufw enable;
  chroot_execute "$_CHROOT_ROOT" ufw status verbose;
  export _UFW_SETUP=1;
}

#chkboot setup detects boot changes on startup
chkboot_setup()
{
  echo_info "$FUNCNAME";
  chroot_package_install "$_CHROOT_ROOT" chkboot;
  sed -i "s#BOOTDISK=/dev/sda#BOOTDISK=${_CHKBOOT_BOOTDISK}#" "${_CHROOT_ROOT}/etc/default/chkboot";
  sed -i "s#BOOTPART=/dev/sda1#BOOTPART=${_CHKBOOT_BOOTPART}#" "${_CHROOT_ROOT}/etc/default/chkboot";
  chroot_execute "$_CHROOT_ROOT" systemctl enable chkboot
}

#TODO new method for a new main user (not 'kali')
user_setup(){
  echo_info "$FUNCNAME";
  echo_warn "Feature not implemented";
}

