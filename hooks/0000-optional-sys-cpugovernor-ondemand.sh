#!/bin/bash
set -e

echo_debug "    Installing packages ..."
chroot_pkginstall cpufrequtils

echo_debug "    Enabling service ..."
chroot_execute 
