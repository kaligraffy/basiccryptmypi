#!/bin/bash
set -e


if [ -n "${_ROOTPASSWD}" ]; then
    echo_debug "Attempting to change root password."
    chroot ${_CHROOT_ROOT} /bin/bash -c "echo root:${_ROOTPASSWD} | /usr/sbin/chpasswd"
else
    echo_warn "SKIPPING: Root password will not be set. _ROOTPASSWD empty or not set."
fi