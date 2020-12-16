#!/bin/bash
set -e

# Compose package actions
echo_debug "Starting compose package actions "
chroot_pkgpurge "${_PKGS_TO_PURGE}"
chroot_pkginstall "${_PKGS_TO_INSTALL}"
