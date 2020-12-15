#!/bin/bash
set -e
IMAGEFILE=${_IMAGEDIR}/${_IMAGENAME}
echo_info "Starting download at $(date)"
wget -nc "${_IMAGEURL}" -O "${IMAGEFILE}" || true
echo_info "Completed download at $(date)"
echo_info "Checking image checksum"
echo ${_IMAGESHA}  $IMAGEFILE | sha256sum --check --status
echo_info "- valid"
