#!/bin/bash
set -eu

echo_debug "Disable the display manager"
chroot_execute "$_CHROOT_ROOT" systemctl set-default multi-user
#to get a gui run startxfce4 on command line
