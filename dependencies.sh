#!/bin/bash
echo_debug "Installing dependencies"
apt-get -qq install \
qemu-user-static \
binfmt-support \
coreutils \
parted \
zip \
grep \
rsync \
xz-utils \
pv \
btrfs-progs 
