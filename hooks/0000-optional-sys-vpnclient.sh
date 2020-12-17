#!/bin/bash
set -e
set -u

echo_debug "Setting OpenVPN up "
_OPENVPN_CONFIG_ZIPFILE=${_OPENVPN_CONFIG_ZIP}
_OPENVPN_CONFIG_ZIPPATH="${_FILEDIR}/${_OPENVPN_CONFIG_ZIPFILE}"

echo_debug "Assuring openvpn installation and config dir"
chroot_package_install openvpn
mkdir -p ${_CHROOT_ROOT}/etc/openvpn

echo_debug "Unzipping provided files into configuraiton dir"
unzip ${_OPENVPN_CONFIG_ZIPPATH} -d ${_CHROOT_ROOT}/etc/openvpn/

echo_debug "Setting AUTOSTART to ALL on OPENVPN config"
sed -i '/^AUTOSTART=/s/^/#/' ${_CHROOT_ROOT}/etc/default/openvpn
sed -i '/^#AUTOSTART="all"/s/^#//' ${_CHROOT_ROOT}/etc/default/openvpn

echo_debug "Enabling service "
chroot_execute systemctl enable openvpn@client
#chroot_execute systemctl enable openvpn@client.service
