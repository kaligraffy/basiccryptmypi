#!/bin/bash
set -eu

# Install and configure cryptsetup nuke package if we were given a password
if [ -n "${_LUKS_NUKE_PASSWORD}" ]; then
    echo_debug "Attempting to install and configure encrypted pi cryptsetup nuke password."
    chroot_package_install "${_CHROOT_ROOT}" cryptsetup-nuke-password
    chroot ${_CHROOT_ROOT} /bin/bash -c "debconf-set-selections <<END
cryptsetup-nuke-password cryptsetup-nuke-password/password string ${_LUKS_NUKE_PASSWORD}
cryptsetup-nuke-password cryptsetup-nuke-password/password-again string ${_LUKS_NUKE_PASSWORD}
END
"
    chroot_execute dpkg-reconfigure -f noninteractive cryptsetup-nuke-password
else
    echo_warn "SKIPPING Cryptsetup NUKE. Nuke password _LUKS_NUKE_PASSWORD not set."
fi
