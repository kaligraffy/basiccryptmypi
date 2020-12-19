#!/bin/bash
set -eu

echo_debug "Disable the display manager"
chroot_execute systemctl set-default multi-user
