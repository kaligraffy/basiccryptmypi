#!/bin/bash
set -eu
install_dependencies() {
  echo_info "$FUNCNAME";
  apt-get -qq install \
        binfmt-support \
        coreutils \
        parted \
        zip \
        grep \
        rsync \
        xz-utils \
        pv ;
}
