#!/bin/bash
set -eu

ufw_setup(){
  echo_info "$FUNCNAME started at $(date) ";

  # Installing packages
  chroot_package_install "$_CHROOT_ROOT" ufw
  chroot_execute "$_CHROOT_ROOT" ufw logging on
  chroot_execute "$_CHROOT_ROOT" ufw default deny outgoing
  chroot_execute "$_CHROOT_ROOT" ufw default deny incoming
  chroot_execute "$_CHROOT_ROOT" ufw default deny routed
  chroot_execute "$_CHROOT_ROOT" ufw allow out 53/udp
  chroot_execute "$_CHROOT_ROOT" ufw allow out 80/tcp
  chroot_execute "$_CHROOT_ROOT" ufw allow out 443/tcp
  chroot_execute "$_CHROOT_ROOT" ufw allow in "${_SSH_PORT}/tcp"
  chroot_execute "$_CHROOT_ROOT" ufw enable
  ufw status verbose
  echo_warn "Firewall setup complete, please review setup and amend as necessary"
}
ufw_setup;
