#!/bin/bash
set -e

# Compose package actions
echo_debug "Starting compose package actions "
chroot_package_purge "${_PKGS_TO_PURGE}"
chroot_package_install "${_PKGS_TO_INSTALL}"
