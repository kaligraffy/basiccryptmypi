#!/bin/bash
set -e

setup_locales(){
echo_debug "Configuring system locale"

echo_debug "Uncommenting locale "${_LOCALE}" for inclusion in generation"
sed -i 's/^# *\(en_US.UTF-8\)/\1/' "${_CHROOT_ROOT}"/etc/locale.gen

echo_debug "Updating /etc/default/locale"
cat << EOF >> "${_CHROOT_ROOT}/etc/default/locale"
LANG="${_LOCALE}"
EOF

echo_debug "Installing locales"
chroot_package_install locales

echo_debug "Updating env variables"
chroot "${_CHROOT_ROOT}" /bin/bash -x <<EOF
export LC_ALL="${_LOCALE}" 2> /dev/null
export LANG="${_LOCALE}"
export LANGUAGE="${_LOCALE}"
EOF

echo_debug "Generating locale"
chroot_execute locale-gen

echo_debug "Updating .bashrc"
cat << EOF >> ${_CHROOT_ROOT}/.bashrc

# Setting locales
export LC_ALL="${_LOCALE}"
export LANG="${_LOCALE}"
export LANGUAGE="${_LOCALE}"
EOF
}
setup_locales
