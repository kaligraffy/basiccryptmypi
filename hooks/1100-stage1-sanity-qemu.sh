#!/bin/bash
set -e

# Sanity check for qemu
if [ ! -f "/usr/bin/qemu-aarch64-static" ]; then
    echo_debug "Can't find arm emulator. Attempting to install ..."
    apt-get -qq install qemu-user-static binfmt-support
    if [ ! -f "/usr/bin/qemu-aarch64-static" ]; then
        echo_error "Still can't find arm emulator."
        exit 1
    fi
fi
