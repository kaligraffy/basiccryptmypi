#!/bin/bash
set -eu


echo_debug "Changing kali user password"
chroot ${_CHROOT_ROOT} /bin/bash -c "echo kali:${_KALI_PASSWORD} | /usr/sbin/chpasswd"
echo_info "Kali user password set"

