#!/bin/bash
set -e

rollback()
{
  echo_error "Rolling back!"
  rm "${image_out_file}" || true;
}

download_image(){
  trap "rollback" ERR SIGINT
  local image_name=$(basename ${_IMAGE_URL})
  mkdir -p "${_FILEDIR}"
  local image_out_file=${_FILEDIR}/${image_name}
  echo_info "Starting download at $(date)"
  wget -nc "${_IMAGE_URL}" -O "${image_out_file}" || true
  echo_info "Completed download at $(date)"
  echo_info "Checking image checksum"
  echo ${_IMAGE_SHA256}  $image_out_file | sha256sum --check --status
  echo_info "- valid"
  trap - ERR SIGINT
}
download_image
