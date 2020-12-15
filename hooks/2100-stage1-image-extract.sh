#!/bin/bash
set -e

mkdir ${_BUILDDIR}/root
mkdir ${_BUILDDIR}/mount

echo_info "Starting extract at $(date)"
echo_debug "Extracting image: ${_IMAGENAME}"
if [ ! -e ${_IMAGEDIR}/cryptmypi.img ]; then
    case ${_IMAGENAME} in
        *.xz)
            xz --decompress --stdout ${_IMAGEDIR}/${_IMAGENAME} > ${_IMAGEDIR}/cryptmypi.img
            ;;
        *.zip)
            unzip -p ${_IMAGEDIR}/${_IMAGENAME} > ${_IMAGEDIR}/cryptmypi.img
            ;;
        *)
            echo_error "Unknown extension type on image: ${_IMAGENAME}"
            exit 1
            ;;
    esac
else 
    echo_debug "${_IMAGEDIR}/cryptmypi.img found, skipping extract"
fi
echo_info "Finished extract at $(date)"
echo_debug "Mounting loopback ..."
loopdev=$(losetup -P -f --show ${_IMAGEDIR}/cryptmypi.img)

mount ${loopdev}p2 ${_BUILDDIR}/mount/
echo_info "Starting copy of root to ${_BUILDDIR}/root $(date)"
cp -a ${_BUILDDIR}/mount/* ${_BUILDDIR}/root/
umount ${_BUILDDIR}/mount
echo_info "Finished copy of root to ${_BUILDDIR}/root $(date)"

mount ${loopdev}p1 ${_BUILDDIR}/mount/boot
echo_info "Starting copy of boot to ${_BUILDDIR}/boot $(date)"
cp -a ${_BUILDDIR}/mount/* ${_BUILDDIR}/root/boot/
umount ${_BUILDDIR}/mount/boot
echo_info "Finished copy of root to ${_BUILDDIR}/root $(date)"

echo_debug "Cleaning loopback ..."
losetup -d ${loopdev}
