#!/bin/bash
set -e

# Precondition check for root powers
if (( $EUID != 0 )); then
    echo_error "ERROR: This script must be run as root/sudo"
    exit 1
fi
