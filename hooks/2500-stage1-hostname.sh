#!/bin/bash
set -e

echo_debug "Setting hostname to ${_HOSTNAME}"
# Overwrites /etc/hostname
echo "${_HOSTNAME}" > "${_CHROOT_ROOT}/etc/hostname"
# Updates /etc/hosts
sed -i "s#^127.0.1.1\s*.*\$#127.0.1.1       ${_HOSTNAME}#" "${_CHROOT_ROOT}/etc/hosts"
