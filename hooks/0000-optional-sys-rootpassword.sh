#!/bin/bash
set -e
set -u

echo_debug "Changing root password"
chroot ${_CHROOT_ROOT} /bin/bash -c "echo root:${_ROOT_PASSWORD} | /usr/sbin/chpasswd"
echo_info "Root password set"

