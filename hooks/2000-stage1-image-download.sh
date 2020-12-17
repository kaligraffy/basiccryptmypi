#!/bin/bash
set -e

IMAGE_NAME=$(basename ${_IMAGEURL})
mkdir -p "${_FILEDIR}"
IMAGE_OUT_FILE=${_FILEDIR}/${IMAGE_NAME}
echo_info "Starting download at $(date)"
wget -nc "${_IMAGEURL}" -O "${IMAGE_OUT_FILE}" || true
echo_info "Completed download at $(date)"
echo_info "Checking image checksum"
echo ${_IMAGESHA}  $IMAGE_OUT_FILE | sha256sum --check --status
echo_info "- valid"
