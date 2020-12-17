#!/bin/bash
dependencies() {
echo_info "$FUNCNAME started at $(date)"
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
btrfs-progs; 
}
