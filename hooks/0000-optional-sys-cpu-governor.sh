#!/bin/bash
set -eu

echo_debug "Installing package cpufrequtils"
chroot_package_install "${_CHROOT_ROOT}" cpufrequtils
echo_info "Use cpufreq-info/systemctl status cpufrequtils to confirm the changes when the device is running"
chroot_execute echo "GOVERNOR=$(_CPU_GOVERNOR)" | sudo tee /etc/default/cpufrequtils
chroot_execute systemctl enable cpufrequtils
