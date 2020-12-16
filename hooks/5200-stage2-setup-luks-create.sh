#!/bin/bash
set -e
set -u

# Create LUKS
echo_debug "Attempting to create LUKS ${_BLKDEV}${_PARTITIONPREFIX}2 ..."
echo "${_LUKSPASSWD}" | cryptsetup -v --cipher ${_LUKSCIPHER} luksFormat ${_BLKDEV}${_PARTITIONPREFIX}2
echo_debug "LUKS created ${_BLKDEV}${_PARTITIONPREFIX}2 ..."
