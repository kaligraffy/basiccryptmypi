#!/bin/bash
set -eu

# Compose package actions
echo_debug "Removing ${_PKGS_TO_PURGE}"
chroot_package_purge "$_CHROOT_ROOT" "${_PKGS_TO_PURGE}"
echo_debug "Installing ${_PKGS_TO_INSTALL}"
chroot_package_install "$_CHROOT_ROOT" "${_PKGS_TO_INSTALL}"
