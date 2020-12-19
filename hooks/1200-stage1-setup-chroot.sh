#!/bin/bash
set -eu

chroot_mount "$_CHROOT_ROOT"
chroot_update "$_CHROOT_ROOT"
