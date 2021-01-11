#!/bin/bash
set -eu
install_dependencies() {
  echo_info "$FUNCNAME";
  apt-get -qq install \
        binfmt-support \
        qemu-user-static \
        coreutils \
        parted \
        zip \
        grep \
        rsync \
        xz-utils \
        pv ;
}
