#!/bin/bash
set -e
echo_info "Starting download at $(date)"
IMAGEFILE=${_IMAGEDIR}/${_IMAGENAME}
#wget -nc "${_IMAGEURL}" -O "${IMAGEFILE}" #TESTING
echo "$_IMAGESHA"  $IMAGEFILE | sha256sum --check --status
#rm ${_IMAGEDIR}/${_IMAGENAME} #TESTING
echo_debug "Image valid"
echo_info "Completed download at $(date)"
