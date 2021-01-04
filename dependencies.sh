#!/bin/bash
set -eu
install_dependencies() {
    echo_info "$FUNCNAME started at $(date)"
    apt-get -qq install \
        binfmt-support \
        coreutils \
        parted \
        zip \
        grep \
        rsync \
        xz-utils \
        pv ;
        #        qemu-user-static \
}
