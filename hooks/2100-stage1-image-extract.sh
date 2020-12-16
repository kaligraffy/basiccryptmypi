#!/bin/bash
set -e

trap 'rm -iRf ${_CHROOT_ROOT}; umountgracefully' ERR
umountgracefully() {
    umount -f ${_BUILDDIR}/boot || true
    umount -f ${_BUILDDIR}/mount || true
    losetup -D ${loopdev}
    rm -Rf ${_BUILDDIR}/mount
    rm -Rf ${_BUILDDIR}/boot
}
IMAGENAME=$(basename ${_IMAGEURL})
IMAGE="${_FILEDIR}/${IMAGENAME}"
EXTRACTEDIMAGE="${_FILEDIR}/extracted.img"

if [ -e "$EXTRACTEDIMAGE" ]; then
    echo_info "$EXTRACTEDIMAGE found, skipping extract"
else
    echo_info "Starting extract at $(date)"
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
    echo_info "Finished extract at $(date)"
fi

mkdir "${_BUILDDIR}/mount"
mkdir "${_BUILDDIR}/boot"
mkdir "${_CHROOT_ROOT}"
echo_debug "Mounting loopback"
loopdev=$(losetup -P -f --show "$EXTRACTEDIMAGE")
mount -o ro ${loopdev}p2 ${_BUILDDIR}/mount/
mount -o ro ${loopdev}p1 ${_BUILDDIR}/boot/
echo_info "Starting copy of boot to ${_CHROOT_ROOT}/ $(date)"

rsync \
--hard-links \
--archive \
--checksum \
--partial \
--info=progress2 \
"${_BUILDDIR}/boot" "${_CHROOT_ROOT}/"

echo_info "Starting copy of / to ${_CHROOT_ROOT}/root $(date)"
rsync \
--hard-links \
--archive \
--checksum \
--partial \
--info=progress2 \
"${_BUILDDIR}/mount" "${_CHROOT_ROOT}"

umountgracefully


