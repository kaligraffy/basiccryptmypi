#!/bin/bash
set -e
# Testing Code only (Remove later)
#return 0;
# End of test code.
IMAGENAME=$(basename ${_IMAGEURL})
mkdir -p "${_FILEDIR}"
IMAGE=${_FILEDIR}/${IMAGENAME}
echo_info "Starting download at $(date)"
wget -nc "${_IMAGEURL}" -O "${IMAGE}" || true
echo_info "Completed download at $(date)"
echo_info "Checking image checksum"
echo ${_IMAGESHA}  $IMAGE | sha256sum --check --status
echo_info "- valid"
