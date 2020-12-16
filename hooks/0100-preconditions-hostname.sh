#!/bin/bash
set -e

if [ -z "${_HOSTNAME}" ]; then
    echo_error "ERROR: '_HOSTNAME' variable not defined"
    exit 1
fi
