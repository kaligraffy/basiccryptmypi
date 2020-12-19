#!/bin/bash
set -eu

echo_debug "Disable the display manager"
chroot_execute "$_CHROOT_ROOT" systemctl set-default multi-user
