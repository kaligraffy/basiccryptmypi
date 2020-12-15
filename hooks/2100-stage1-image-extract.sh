#!/bin/bash
set -e

IMAGE="${_IMAGEDIR}/${_IMAGENAME}"
EXTRACTEDIMAGE="${_IMAGEDIR}/extracted.img"

mkdir $_BUILDDIR/mount

echo_info "Starting extract at $(date)"
if [ -e "$EXTRACTEDIMAGE" ]; then
    echo_info "$EXTRACTEDIMAGE found"
else
    case ${IMAGE} in
        *.xz)
            echo_info "Extracting with xz"
            xz --decompress --stdout ${IMAGE} > $EXTRACTEDIMAGE
            ;;
        *.zip)
            echo_info "Extracting with unzip"
            unzip -p $IMAGE > $EXTRACTEDIMAGE
            ;;
        *)
            echo_error "Unknown extension type on image: $IMAGE"
            exit 1
            ;;
    esac
fi

# At this point, there is a a decompressed image in the IMAGE/folder
# Now we

echo_info "Finished extract at $(date)"
exit
echo_debug "Mounting loopback ..."
loopdev=$(losetup -P -f --show "$EXTRACTEDIMAGE")

echo_debug "Unmounted $_BUILDDIR/boot $(date)"
mount ${loopdev}p2 ${_BUILDDIR}/mount/
mount ${loopdev}p1 ${_BUILDDIR}/mount/boot

echo_info "Starting copy of boot to ${_BUILDDIR}/boot $(date)"
cp -a ${_BUILDDIR}/mount ${_BUILDDIR}/root
echo_info "Finished copy of boot to ${_BUILDDIR}/boot $(date)"

echo_debug "Unmounted ${_BUILDDIR}/boot $(date)"
umount ${_BUILDDIR}/mount/boot
umount ${_BUILDDIR}/mount
rmdir ${_BUILDDIR}/mount
echo_debug "Cleaning loopback ..."
losetup -d ${loopdev}
