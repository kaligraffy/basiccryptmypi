#!/bin/bash
set -eu
declare -x _UFW_SETUP=0;

#used by wifi_setup and initramfs_wifi_setup

#set dns in resolv.conf for setup only or none dnssec setup
simple_dns_setup(){
  echo_function_start;
  echo -e "nameserver $_DNS1\nnameserver $_DNS2" > "${_CHROOT_DIR}/etc/resolv.conf";
}

#create wifi connection to a router/hotspot on boot
#requires: , optional: wifi_setup
initramfs_wifi_setup(){
# REFERENCE:
#    http://www.marcfargas.com/posts/enable-wireless-debian-initramfs/
#    https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlock_via_wifi
#    http://retinal.dehy.de/docs/doku.php?id=technotes:raspberryrootnfs
#    use the 'fing' app to find the device if mdns isn't working
  echo_function_start;
  local wifi_psk;
  wifi_psk="$(wpa_passphrase "${_WIFI_SSID}" "${_WIFI_PASSWORD}" | grep "psk=" | grep -v "#psk" | sed 's/^[\t]*//g')"

  echo_debug "Attempting to set initramfs WIFI up "
  
  # Update /boot/cmdline.txt to boot crypt
  if ! grep -wq "${_INITRAMFS_WIFI_IP}" "${_CHROOT_DIR}/boot/cmdline.txt" ; then
    sed -i "s#rootwait#ip=${_INITRAMFS_WIFI_IP} rootwait#g" "${_CHROOT_DIR}/boot/cmdline.txt"
  fi

  echo_debug "Copying scripts";
  cp -p "${_FILE_DIR}/initramfs-scripts/zz-brcm" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/"
  cp -p "${_FILE_DIR}/initramfs-scripts/a_enable_wireless" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/init-premount/";
  cp -p "${_FILE_DIR}/initramfs-scripts/hook_enable_wireless" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/"
  cp -p "${_FILE_DIR}/initramfs-scripts/kill_wireless" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/local-bottom/"
  
  sed -i "s#_WIFI_INTERFACE#${_WIFI_INTERFACE}#g" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/init-premount/a_enable_wireless";
  sed -i "s#_INITRAMFS_WIFI_DRIVERS#${_INITRAMFS_WIFI_DRIVERS}#g" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/hook_enable_wireless";
 
  echo_debug "Creating wpa_supplicant file";
  cat <<- EOT > "${_CHROOT_DIR}/etc/initramfs-tools/wpa_supplicant.conf"
ctrl_interface=/tmp/wpa_supplicant
network={
 ssid="${_WIFI_SSID}"
 scan_ssid=1
 key_mgmt=WPA-PSK
 ${wifi_psk}
}
EOT

  # Adding modules to initramfs modules
  for driver in ${_INITRAMFS_WIFI_DRIVERS}; do
    atomic_append "${driver}" "${_CHROOT_DIR}/etc/initramfs-tools/modules"
  done
  echo_debug "initramfs wifi completed";
}

#configure system on decrypt to connect to a hotspot specified in env file
wifi_setup(){
  echo_function_start;
  local wifi_psk;
  wifi_psk="$(wpa_passphrase "${_WIFI_SSID}" "${_WIFI_PASSWORD}" | grep "psk=" | grep -v "#psk" | sed 's/^[\t]*//g')"
  echo_debug "Creating wpa_supplicant file"
  cat <<- EOT > "${_CHROOT_DIR}/etc/wpa_supplicant.conf"
ctrl_interface=/var/run/wpa_supplicant
network={
 ssid="${_WIFI_SSID}"
 scan_ssid=1
 proto=WPA RSN
 key_mgmt=WPA-PSK
 pairwise=CCMP TKIP
 group=CCMP TKIP
 ${wifi_psk}
}
EOT

  echo_debug "Updating /etc/network/interfaces file"
  if ! grep -qw "# The wifi interface" "${_CHROOT_DIR}/etc/network/interfaces" ; then
    cat <<- EOT >> "${_CHROOT_DIR}/etc/network/interfaces"
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
  cp -pr "${_FILE_DIR}/wifi-scripts/sys-wifi-connect.sh" "${_CHROOT_DIR}/usr/local/bin/sys-wifi-connect.sh"
  sed -i "s|_WIFI_INTERFACE|${_WIFI_INTERFACE}|g" "${_CHROOT_DIR}/usr/local/bin/sys-wifi-connect.sh";
  echo_debug "Add to cron to start at boot (before login)"
  cp -pr "${_FILE_DIR}/wifi-scripts/sys-wifi" "${_CHROOT_DIR}/etc/cron.d/sys-wifi"

}

#set up ssh
#requires: , optional: firewall_setup
ssh_setup(){
  echo_function_start;

  sshd_config="${_CHROOT_DIR}/etc/ssh/sshd_config"
  ssh_authorized_keys="${_CHROOT_DIR}/root/.ssh/authorized_keys"

   # Creating box's default user own key
  create_ssh_key;

  # Append our key to the default user's authorized_keys file
  echo_debug "Creating authorized_keys file"
  cat "${_SSH_LOCAL_KEYFILE}.pub" > "${ssh_authorized_keys}"
  chmod 600 "${ssh_authorized_keys}"

  # Update sshd settings
  cp -p "${sshd_config}" "${sshd_config}.bak"
  if ! grep -q -w "#New SSH Config" "${sshd_config}"; then
  cat <<- EOT >> "${sshd_config}"
#New SSH Config
PasswordAuthentication ${_SSH_PASSWORD_AUTHENTICATION}
Port ${_SSH_PORT}
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
PermitRootLogin yes
Protocol 2
ClientAliveInterval 180
AllowUsers ${_NEW_DEFAULT_USER} root
MaxAuthTries 3
MaxSessions 2
EOT
  fi
  
#TODO sensible ssh default configuration
#       - OpenSSH option: AllowTcpForwarding                      [ SUGGESTION ]
#     - OpenSSH option: ClientAliveCountMax                     [ SUGGESTION ]
#     - OpenSSH option: ClientAliveInterval                     [ OK ]
#     - OpenSSH option: Compression                             [ SUGGESTION ]
#     - OpenSSH option: FingerprintHash                         [ OK ]
#     - OpenSSH option: GatewayPorts                            [ OK ]
#     - OpenSSH option: IgnoreRhosts                            [ OK ]
#     - OpenSSH option: LoginGraceTime                          [ OK ]
#     - OpenSSH option: PermitRootLogin                         [ OK ]
#     - OpenSSH option: PermitUserEnvironment                   [ OK ]
#     - OpenSSH option: PermitTunnel                            [ OK ]
#     - OpenSSH option: Port                                    [ SUGGESTION ]
#     - OpenSSH option: PrintLastLog                            [ OK ]
#     - OpenSSH option: StrictModes                             [ OK ]
#     - OpenSSH option: TCPKeepAlive                            [ SUGGESTION ]
#     - OpenSSH option: UseDNS                                  [ OK ]
#     - OpenSSH option: X11Forwarding                           [ SUGGESTION ]
#     - OpenSSH option: AllowAgentForwarding                    [ SUGGESTION ]
#     - OpenSSH option: AllowGroups                             [ NOT FOUND ]
#   
  #OPENS UP YOUR SSH PORT
  if (( _UFW_SETUP == 1 )) ; then
    chroot_execute "ufw allow in ${_SSH_PORT}/tcp";
    chroot_execute 'ufw enable';
    chroot_execute 'ufw status verbose';
  fi
}

#setup dropbear in initramfs
#requires: ssh_setup
dropbear_setup(){
  echo_function_start;
  if [ ! -f "${_SSH_LOCAL_KEYFILE}" ]; then
      echo_error "SSH keyfile '${_SSH_LOCAL_KEYFILE}' could not be found. Exiting";
      exit 1;
  fi

  # Installing packages
  chroot_package_install dropbear dropbear-initramfs cryptsetup-initramfs

  atomic_append "DROPBEAR_OPTIONS='-p $_SSH_PORT -RFEjk -c /bin/unlock.sh'" "${_CHROOT_DIR}/etc/dropbear-initramfs/config";

  #TEST test code - remove later
  #atomic_append "DROPBEAR_OPTIONS='-p $_SSH_PORT -RFEjk'" "${_CHROOT_DIR}/etc/dropbear-initramfs/config";
  
  # Now append our key to dropbear authorized_keys file
  echo_debug "checking ssh key for root@hostname. make sure any host key has this comment.";
  if ! grep -qw "root@${_HOSTNAME}" "${_CHROOT_DIR}/etc/dropbear-initramfs/authorized_keys" ; then
    cat "${_SSH_LOCAL_KEYFILE}.pub" >> "${_CHROOT_DIR}/etc/dropbear-initramfs/authorized_keys";
  fi
  chmod 600 "${_CHROOT_DIR}/etc/dropbear-initramfs/authorized_keys";

  # Update dropbear for some sleep in initramfs
  sed -i 's#run_dropbear \&#sleep 5\nrun_dropbear \&#g' "${_CHROOT_DIR}/usr/share/initramfs-tools/scripts/init-premount/dropbear";
 
  # Unlock Script
  cp -p "${_FILE_DIR}/initramfs-scripts/hook_dropbear_unlock" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/";
  cp -p "${_FILE_DIR}/initramfs-scripts/unlock.sh" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/unlock.sh";
  sed -i "s#ENCRYPTED_VOLUME_PATH#${_ENCRYPTED_VOLUME_PATH}#g" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/unlock.sh";
 
  # We not using provided dropbear keys (or backuping generating ones for later usage)
  rm "${_CHROOT_DIR}/etc/dropbear-initramfs/dropbear_rsa_host_key" || true;
  rm "${_CHROOT_DIR}/etc/dropbear-initramfs/dropbear_ed25519_host_key" || true;
  rm "${_CHROOT_DIR}/etc/dropbear-initramfs/dropbear_ecdsa_host_key" || true;
  rm "${_CHROOT_DIR}/etc/dropbear/dropbear_rsa_host_key" || true;
  rm "${_CHROOT_DIR}/etc/dropbear/dropbear_ed25519_host_key" || true;
  rm "${_CHROOT_DIR}/etc/dropbear/dropbear_ecdsa_host_key" || true;

  #backup_dropbear_key "${_CHROOT_DIR}/etc/dropbear-initramfs/dropbear_rsa_host_key";
}

#disable the gui 
display_manager_setup(){
  echo_function_start;
  chroot_execute 'systemctl set-default multi-user'
  echo_warn "To get a gui run startxfce4 on command line"
}

luks_nuke_setup(){
 echo_function_start;

# Install and configure cryptsetup nuke package if we were given a password
  if [ -n "${_LUKS_NUKE_PASSWORD}" ]; then
    echo_debug "Attempting to install and configure encrypted pi cryptsetup nuke password."
    chroot_package_install cryptsetup-nuke-password
    chroot "${_CHROOT_DIR}" /bin/bash -c "debconf-set-selections <<- EOT
cryptsetup-nuke-password cryptsetup-nuke-password/password string ${_LUKS_NUKE_PASSWORD}
cryptsetup-nuke-password cryptsetup-nuke-password/password-again string ${_LUKS_NUKE_PASSWORD}
EOT
"
  chroot_execute 'dpkg-reconfigure -f noninteractive cryptsetup-nuke-password'
  else
      echo_warn "Nuke password _LUKS_NUKE_PASSWORD not set. Skipping."
  fi
}

#sets cpu performance mode (useful for running off battery)
cpu_governor_setup(){
  echo_function_start;
  chroot_package_install cpufrequtils;
  echo_warn "Use cpufreq-info/systemctl status cpufrequtils to confirm the changes when the device is running";
  echo "GOVERNOR=${_CPU_GOVERNOR}" | tee "${_CHROOT_DIR}/etc/default/cpufrequtils";
  chroot_execute 'systemctl enable cpufrequtils';
}

#custom hostname setup
hostname_setup(){
  echo_function_start;
  # Overwrites /etc/hostname
  echo "${_HOSTNAME}" > "${_CHROOT_DIR}/etc/hostname";
  # Updates /etc/hosts
  sed -i "s#^127.0.0.1       kali#127.0.0.1  ${_HOSTNAME}#" "${_CHROOT_DIR}/etc/hosts";
}

#sets the root password
root_password_setup(){
  echo_function_start;
  chroot "${_CHROOT_DIR}" /bin/bash -c "echo root:${_ROOT_PASSWORD} | /usr/sbin/chpasswd"
}

#sets the kali user password
user_password_setup(){
  echo_function_start;
  chroot "${_CHROOT_DIR}" /bin/bash -c "echo kali:${_USER_PASSWORD} | /usr/sbin/chpasswd"
}

#setup a vpn client
vpn_client_setup(){
  echo_function_start;

  _OPENVPN_CONFIG_ZIPFILE="${_OPENVPN_CONFIG_ZIP}"
  _OPENVPN_CONFIG_ZIPPATH="${_FILE_DIR}/${_OPENVPN_CONFIG_ZIPFILE}"

  echo_debug "Assuring openvpn installation and config dir"
  chroot_package_install openvpn
  mkdir -p "${_CHROOT_DIR}/etc/openvpn"

  echo_debug "Unzipping provided files into configuration dir"
  unzip "${_OPENVPN_CONFIG_ZIPPATH}" -d "${_CHROOT_DIR}/etc/openvpn/"

  echo_debug "Setting AUTOSTART to ALL on OPENVPN config"
  sed -i '/^AUTOSTART=/s/^/#/' "${_CHROOT_DIR}/etc/default/openvpn"
  sed -i '/^#AUTOSTART="all"/s/^#//' "${_CHROOT_DIR}/etc/default/openvpn"

  echo_debug "Enabling service "
  chroot_execute 'systemctl enable openvpn@client.service'
}


#installs clamav and update/scanning daemons, updates to most recent definitions
clamav_setup(){
  echo_function_start;
  chroot_package_install clamav clamav-daemon
  chroot_execute 'systemctl enable clamav-freshclam.service'
  chroot_execute 'systemctl enable clamav-daemon.service'
  chroot_execute 'freshclam'
  echo_debug "clamav installed"
}

#simulates a hardware clock
fake_hwclock_setup(){
  echo_function_start;
  chroot_package_install fake-hwclock
  # set clock even if saved value appears to be in the past
  # sed -i "s|^#FORCE=force|FORCE=force|"  "${_CHROOT_DIR}/etc/default/fake-hwclock"
  chroot_execute 'systemctl enable fake-hwclock'
}

#update system
apt_upgrade(){
  echo_function_start;
  chroot_execute "$_APT_CMD update"
  chroot_execute "$_APT_CMD upgrade"
}

#install and configure docker
#TODO Test docker
docker_setup(){
# REFERENCES
#   https://www.docker.com/blog/happy-pi-day-docker-raspberry-pi/
#   https://github.com/docker/docker.github.io/blob/595616145a53d68fb5be1d603e97666cefcb5293/install/linux/docker-ce/debian.md
#   https://docs.docker.com/engine/install/debian/
#   https://gist.github.com/decidedlygray/1288c0265457e5f2426d4c3b768dfcef
  echo_function_start;
  echo_warn "Docker may conflict with VPN services/connections"
#   echo_debug "    Updating iptables  (issue: default kali iptables was stalling)"
#   systemctl start and stop commands would hang/stall due to pristine iptables on kali-linux-2020.1a-rpi3-nexmon-64.img.xz
#  chroot_package_install iptables
#   chroot_execute update-alternatives --set iptables /usr/sbin/iptables-legacy
#   chroot_execute update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Needed to avoid "cgroups: memory cgroup not supported on this system"
#   see https://github.com/moby/moby/issues/35587
#       cgroup_enable works on kernel 4.9 upwards
#       cgroup_memory will be dropped in 4.14, but works on < 4.9
#       keeping both for now
  sed -i "s#rootwait#cgroup_enable=memory cgroup_memory=1 rootwait#g" "${_CHROOT_DIR}/boot/cmdline.txt"
  chroot_package_install docker.io
  chroot_execute 'systemctl enable docker'
  echo_debug "docker installed";
}

#install and remove custom packages
packages_setup(){
  echo_function_start;
  chroot_package_purge "${_PKGS_TO_PURGE}";
  chroot_package_install "${_PKGS_TO_INSTALL}";
}

#sets up aide to run at midnight each night
aide_setup(){
  echo_function_start;
  chroot_package_install aide
  chroot_execute 'aideinit'
  chroot_execute 'mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db'
  cp -p "${_FILE_DIR}/aide-scripts/aide-check" "${_CHROOT_DIR}/etc/cron.d/aide-check"
}

#basic snapper install for use with btrfs, snapshots root directory in its entirety with default settings,
snapper_setup(){
  echo_function_start;
  chroot_package_install snapper 
  chroot_execute 'systemctl disable snapper-boot.timer'
  chroot_execute 'systemctl disable snapper-timeline.timer'
  echo_warn "Snapper installed, but not configured, services are disabled, enable via systemctl";
}

#secure network time protocol configuration, also installs ntpdate client for manually pulling the time
#requires: , optional: firewall_setup
ntpsec_setup(){
  echo_function_start;
  chroot_package_install ntpsec ntpsec-doc ntpsec-ntpdate
  sed -i "s|^# server time.cloudflare.com nts|server time.cloudflare.com:123 iburst nts \nserver nts.sth1.ntp.se:123 iburst nts\nserver nts.sth2.ntp.se:123 iburst nts|" "/etc/ntpsec/ntp.conf" "${_CHROOT_DIR}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 0.debian.pool.ntp.org iburst|#pool 0.debian.pool.ntp.org iburst|" "${_CHROOT_DIR}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 1.debian.pool.ntp.org iburst|#pool 1.debian.pool.ntp.org iburst|" "${_CHROOT_DIR}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 2.debian.pool.ntp.org iburst|#pool 2.debian.pool.ntp.org iburst|" "${_CHROOT_DIR}/etc/ntpsec/ntp.conf"
  sed -i "s|^pool 3.debian.pool.ntp.org iburst|#pool 3.debian.pool.ntp.org iburst|" "${_CHROOT_DIR}/etc/ntpsec/ntp.conf"
  
  chroot_execute 'mkdir -p /var/log/ntpsec'
  chroot_execute 'chown ntpsec:ntpsec /var/log/ntpsec'
  chroot_execute 'systemctl enable ntpsec.service'

  if (( _UFW_SETUP == 1 )) ; then
    chroot_execute 'ufw allow out 123/tcp';
    chroot_execute 'ufw enable';
    chroot_execute 'ufw status verbose';
  fi
}

#config iodine
iodine_setup(){
  # REFERENCE:
  #   https://davidhamann.de/2019/05/12/tunnel-traffic-over-dns-ssh/
  echo_function_start;
  chroot_package_install iodine

  # Create initramfs hook file for iodine
  cp -p "${_FILE_DIR}/initramfs-scripts/zz-iodine" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/"

  # Replace variables in iodine hook file
  sed -i "s#IODINE_PASSWORD#${_IODINE_PASSWORD}#g" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/zz-iodine"
  sed -i "s#IODINE_DOMAIN#${_IODINE_DOMAIN}#g" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/zz-iodine"

  # Create initramfs script file for iodine
  cp -p "${_FILE_DIR}/initramfs-scripts/iodine" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/init-premount/";
  echo_debug "iodine setup complete";
}

#vlc_setup, fix broken audio
vlc_setup(){
  echo_function_start;
  chroot_package_install vlc
  
  #stuttery audio fix on rpi4
  if ! grep -qx "load-module module-udev-detect tsched=0" "${_CHROOT_DIR}/etc/pulse/default.pa" ; then
    sed -i "s|load-module module-udev-detect|load-module module-udev-detect tsched=0|" "${_CHROOT_DIR}/etc/pulse/default.pa"
  fi
  
  #bump your gpu memory up too (should make video less bumpy)
  atomic_append "gpu_mem=128" "${_CHROOT_DIR}/boot/config.txt";
}

#sysctl hardening (taken fron lynis audit)
#TODO test commented sysctl.conf variables
sysctl_hardening_setup(){
  echo_function_start;
  cp -p "${_CHROOT_DIR}/etc/sysctl.conf" "${_CHROOT_DIR}/etc/sysctl.conf.bak";
  atomic_append "#dev.tty.ldisc_autoload = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#fs.protected_fifos = 2" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#fs.protected_hardlinks = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#fs.protected_regular = 2" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#fs.protected_symlinks = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#fs.suid_dumpable = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.core_uses_pid = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.ctrl-alt-del = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.dmesg_restrict = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.kptr_restrict = 2" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.modules_disabled = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.perf_event_paranoid = 3" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.randomize_va_space = 2" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.sysrq = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "#kernel.unprivileged_bpf_disabled = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.accept_redirects = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.accept_source_route = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.bootp_relay =  0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.forwarding = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.log_martians = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.mc_forwarding = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.proxy_arp = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.rp_filter = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.all.send_redirects = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.default.accept_redirects = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.default.accept_source_route = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.conf.default.log_martians = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.icmp_echo_ignore_broadcasts = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.icmp_ignore_bogus_error_responses = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.tcp_syncookies = 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv4.tcp_timestamps = 0 1" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv6.conf.all.accept_redirects = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv6.conf.all.accept_source_route = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv6.conf.default.accept_redirects = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
  atomic_append "net.ipv6.conf.default.accept_source_route = 0" "${_CHROOT_DIR}/etc/sysctl.conf";
}

#automatically log you in after unlocking your encrypted drive, without a password...somehow. GUI only.
passwordless_login_setup(){
  echo_function_start;
  sed -i "s|^#greeter-hide-users=false|greeter-hide-users=false|" "${_CHROOT_DIR}/etc/lightdm/lightdm.conf"
  sed -i "s|^#autologin-user=$|autologin-user=${_PASSWORDLESS_LOGIN_USER}|" "${_CHROOT_DIR}/etc/lightdm/lightdm.conf"
  sed -i "s|^#autologin-user-timeout=0|autologin-user-timeout=0|" "${_CHROOT_DIR}/etc/lightdm/lightdm.conf"
}

#enable bluetooth
bluetooth_setup(){
  echo_function_start;
  chroot_package_install bluez
  chroot_execute 'systemctl enable bluetooth'              
  #TODO setup some bluetooth devices you might have already
}

#TODO Finish apparmor setup method off
# Installs apparmor
apparmor_setup(){
  echo_function_start;
  chroot_package_install apparmor apparmor-profiles-extra apparmor-utils
  echo_warn "PACKAGES INSTALLED, NO KERNEL PARAMS CONFIGURED. PLEASE CONFIGURE MANUALLY";
  #add apparmor=1 etc to cmdline.txt
  #build kernel with apparmor options. WIP
  chroot_execute 'systemctl enable apparmor.service'

}

#firejail setup
firejail_setup(){
  echo_function_start;
  chroot_package_install firejail firejail-profiles firetools
  chroot_execute 'firecfg'
  #TODO firejail configuration for hardened malloc, apparmor integration
}

#randomize mac on reboot
random_mac_on_reboot_setup(){
#https://wiki.archlinux.org/index.php/MAC_address_spoofing#Automatically
  echo_function_start;
  chroot_package_install macchanger 
  cp -p "${_FILE_DIR}/random-mac-scripts/macspoof" "${_CHROOT_DIR}/etc/systemd/system/macspoof@${_WIFI_INTERFACE}.service";
  chroot_execute "systemctl enable macspoof@${_WIFI_INTERFACE}"
}

#configures two ipv4 ip addresses as your global dns
#enables dnssec and DNSOverTLS
#disables mdns, llmnr
#credits: https://andrea.corbellini.name/2020/04/28/ubuntu-global-dns/
#requires: , optional: firewall_setup
dns_setup(){
  echo_function_start;
  chroot_execute 'systemctl disable resolvconf'                                                                                                           
  chroot_execute 'systemctl enable systemd-resolved'
  sed -i "s|^#DNS=|DNS=${_DNS1}|" "${_CHROOT_DIR}/etc/systemd/resolved.conf";
  sed -i "s|^#FallbackDNS=|FallbackDNS=${_DNS2}|" "${_CHROOT_DIR}/etc/systemd/resolved.conf";
  sed -i "s|^#DNSSEC=no|DNSSEC=true|" "${_CHROOT_DIR}/etc/systemd/resolved.conf";
  sed -i "s|^#DNSOverTLS=no|DNSOverTLS=yes|" "${_CHROOT_DIR}/etc/systemd/resolved.conf";
  sed -i "s|^#MulticastDNS=yes|MulticastDNS=no|" "${_CHROOT_DIR}/etc/systemd/resolved.conf";
  sed -i "s|^#LLMNR=yes|LLMNR=no|" "${_CHROOT_DIR}/etc/systemd/resolved.conf";
  
  cat <<- EOT > "${_CHROOT_DIR}/etc/NetworkManager/conf.d/dns.conf"
[main]
dns=none
systemd-resolved=false

[connection]
llmnr=no
mdns=no
EOT

  #add resolved dns to top of /etc/systemd/resolved.conf for use with NetworkManager:
  atomic_append "nameserver 127.0.0.53" "${_CHROOT_DIR}/etc/systemd/resolved.conf"
  
  echo_debug "creating symlink";
  touch "${_CHROOT_DIR}/etc/resolv.conf"
  mv "${_CHROOT_DIR}/etc/resolv.conf" "${_CHROOT_DIR}/etc/resolv.conf.backup";
  chroot_execute 'ln -s /etc/systemd/resolved.conf /etc/resolv.conf';
  echo_debug "DNS configured - remember to keep your clock up to date (date -s XX:XX) or DNSSEC Certificate errors may occur";
  
  if (( _UFW_SETUP == 1 )); then
    chroot_execute 'ufw allow out 853/tcp';
    chroot_execute 'ufw enable';
  fi
  #needs: 853/tcp, doesn't need as we disable llmnr and mdns: 5353/udp,5355/udp
}

#installs a basic firewall
#TODO replace with firewalld
#this must be called before ssh_setup, dns_setup, ntpsec_setup or the script 
#will not work correctly
#TODO remove flags for ufw and check if ufw is installed instead using chroot_execute
firewall_setup(){
  echo_function_start;

  # Installing packages
  chroot_package_install ufw;
  chroot_execute 'ufw logging high';
  chroot_execute 'ufw default deny outgoing';
  chroot_execute 'ufw default deny incoming';
  chroot_execute 'ufw default deny routed';
  
  chroot_execute 'ufw allow out 53/udp';
  chroot_execute 'ufw allow out 80/tcp';
  chroot_execute 'ufw allow out 443/tcp';
  
  chroot_execute 'ufw enable';
  chroot_execute 'ufw status verbose';
  declare -x _UFW_SETUP=1;
}

#chkboot setup detects boot changes on startup
chkboot_setup(){
  echo_function_start;
  local boot_partition;
  local prefix="";

  chroot_execute 'mkdir -p /var/lib/chkboot'
  
  chroot_package_install chkboot;
  
  #if the device contains mmcblk, prefix is set so the device name is picked up correctly
  if [[ "${_CHKBOOT_BOOTDISK}" == *'mmcblk'* ]]; then
    prefix='p'
  fi
  #Set the proper name of the output block device's partitions
  #e.g /dev/sda1 /dev/sda2 etc.
  boot_partition="${_CHKBOOT_BOOTDISK}${prefix}1"
  
  
  sed -i "s#BOOTDISK=/dev/sda#BOOTDISK=${_CHKBOOT_BOOTDISK}#" "${_CHROOT_DIR}/etc/default/chkboot";
  sed -i "s#BOOTPART=/dev/sda1#BOOTPART=${boot_partition}#" "${_CHROOT_DIR}/etc/default/chkboot";
  
  chroot_execute 'systemctl enable chkboot'
}

#TODO test this
#Test this
user_setup(){
  echo_function_start;
  local default_user='kali'
  chroot_execute "deluser ${default_user}"
  chroot_execute "adduser ${_NEW_DEFAULT_USER}"
}

#TODO finish this off
#sets up a vnc server on your device
#requires: , optional: firewall_setup ssh_setup
vnc_setup(){
  echo_function_start;
  chroot_package_install tightvncserver
  local vnc_user='vnc'; #new vnc user is better
  chroot_execute "adduser \"${vnc_user}\""
  vnc_user_home=;
  #run and kill vnc server once to set up the directory structure
  cmd="echo \"${VNC_PASSWORD}\" | vncpasswd -f > \"${vnc_user_home}/.vnc/passwd\""
  chroot_execute $cmd
    
  if (( _UFW_SETUP == 1 )); then
    chroot_execute 'ufw allow in 5900/tcp';
    chroot_execute 'ufw allow in 5901/tcp';
    chroot_execute 'ufw enable';
    chroot_execute 'ufw status verbose';
  fi
}

#TODO Test sftp
#requires: ssh_setup, optional: firewall_setup
sftp_setup(){
  echo_function_start;

  chroot_package_install openssh-sftp-server
  chroot_execute 'groupadd sftp_users'
  chroot_execute 'useradd -g sftp_users -d /data/sftp/upload -s /sbin/nologin sftp'
  chroot_execute "/bin/bash -c echo sftp:${_SFTP_PASSWORD} | /usr/sbin/chpasswd"
 
  chroot_execute 'mkdir -p /data/sftp/upload'
  chroot_execute 'chown -R root:sftp_users /data/sftp'
  chroot_execute 'chown -R sftp:sftp_users /data/sftp/upload'


  cat <<- EOT > "${_CHROOT_DIR}/etc/ssh/ssh_config.d/sftp_config"
Match Group sftp_users
ChrootDirectory /data/%u
ForceCommand internal-sftp
EOT

  if (( _UFW_SETUP == 1 )); then
    chroot_execute "ufw allow in ${_SSH_PORT}/tcp";
    chroot_execute 'ufw enable';    
    chroot_execute 'ufw status verbose';
  fi
}


#MDNS daemon setup - WIP
#TODO test initramfs avahi
#requires: hostname_setup ssh_setup , optional: firewall_setup
avahi_setup(){
  echo_function_start;

  chroot_package_install avahi-daemon libnss-mdns
  chroot_execute 'systemctl enable avahi-daemon'
  sed -i "s|<port>22</port>|<port>${_SSH_PORT}</port>|" "${_CHROOT_DIR}/usr/share/doc/avahi-daemon/examples/ssh.service";
  cp -p "${_CHROOT_DIR}/usr/share/doc/avahi-daemon/examples/ssh.service" "${_CHROOT_DIR}/etc/avahi/services/ssh.service";
  
  
  #make avahi work in initramfs too
  cp -p "${_FILE_DIR}/initramfs-scripts/b_enable_avahi_daemon" "${_CHROOT_DIR}/etc/initramfs-tools/scripts/init-premount/";
  cp -p "${_FILE_DIR}/initramfs-scripts/hook_enable_avahi_daemon" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/";
  sed -i "s|_SSH_PORT|${_SSH_PORT}|" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/hook_enable_avahi_daemon";
  cp -p "${_CHROOT_DIR}/etc/avahi/avahi-daemon.conf" "${_CHROOT_DIR}/etc/initramfs-tools/avahi-daemon.conf";
  sed -i "s|#enable-dbus=yes|enable-dbus=no|" "${_CHROOT_DIR}/etc/initramfs-tools/avahi-daemon.conf";
  
  #Firewall rules for mdns
  if (( _UFW_SETUP == 1 )); then
    chroot_execute 'ufw allow in 5353/udp';
    chroot_execute 'ufw enable';
    chroot_execute 'ufw status verbose';
  fi
}


#TODO Test
#other stuff - add your own!
miscellaneous_setup(){
  echo_function_start;
  #suppress dmesgs in stdout
  echo "@reboot root /bin/sh echo '1' > /proc/sys/kernel/printk" > "${_CHROOT_DIR}/etc/cron.d/suppress-dmesg"
  
  #disable splash on startup
  atomic_append "disable_splash=1" "${_CHROOT_DIR}/boot/config.txt"
  
  #set boot to be readonly
  sed -i "s#/boot           vfat    defaults          0       2#/boot           vfat    defaults,noatime,ro,errors=remount-ro          0       2#" \
  "${_CHROOT_DIR}/etc/fstab";

}

