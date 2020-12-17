#!/bin/bash
set -e

umountgracefully() {
    umount  "${_BUILDDIR}/mount" || true
    umount  "${_BUILDDIR}/boot" || true
    losetup -d "${loopdev}p1" || true
    losetup -d "${loopdev}p2" || true
    losetup -D || true
    rm -rf ${_BUILDDIR}/mount || true
    rm -rf ${_BUILDDIR}/boot || true
}

rollback()
{
    echo_error "Rolling back!"
    rm -rf "${_CHROOT_ROOT}" || true;
    umountgracefully
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
            trap "rm -f $EXTRACTEDIMAGE; exit 1" ERR SIGINT
            xz --decompress --stdout ${IMAGE} > "$EXTRACTEDIMAGE"
            trap - ERR SIGINT 
            ;;
        *.zip)
            echo_info "Extracting with unzip"
            unzip -p $IMAGE > "$EXTRACTEDIMAGE"
            ;;
        *)
            echo_error "Unknown extension type on image: $IMAGE"
            exit 1
            ;;
    esac
    echo_info "Finished extract at $(date)"
fi

trap "rollback" ERR SIGINT
echo_debug "Mounting loopback";
loopdev=$(losetup -P -f --show "$EXTRACTEDIMAGE");
partprobe ${loopdev};
mkdir "${_BUILDDIR}/mount"
mkdir "${_BUILDDIR}/boot"
mkdir "${_CHROOT_ROOT}"
mount ${loopdev}p2 ${_BUILDDIR}/mount
mount ${loopdev}p1 ${_BUILDDIR}/boot
echo_info "Starting copy of boot to ${_CHROOT_ROOT}/boot at $(date)"
rsync \
--hard-links \
--archive \
--verbose \
--partial \
--progress \
--info=progress2 "${_BUILDDIR}/boot" "${_CHROOT_ROOT}/"

echo_info "Starting copy of / to ${_CHROOT_ROOT} at $(date)"
rsync \
--hard-links \
--archive \
--verbose \
--partial \
--progress \
--info=progress2 "${_BUILDDIR}/mount/"* "${_CHROOT_ROOT}"
trap - ERR SIGINT
unmountgracefully
