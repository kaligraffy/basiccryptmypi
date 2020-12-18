#!/bin/bash
set -e
set -u
fs_type=$_FILESYSTEM_TYPE

# TODO(kaligraffy) - variable duplication, needs sorting ideally
export _CHROOT_ROOT=/mnt/cryptmypi
    
echo_debug "Attempt to unmount just to be safe "
umount ${_OUTPUT_BLOCK_DEVICE}* || true
umount ${_CHROOT_ROOT} || {
    umount -l ${_CHROOT_ROOT} || true
    umount -f ${_ENCRYPTED_VOLUME_PATH} || true
}

[ -d ${_CHROOT_ROOT} ] && rm -r ${_CHROOT_ROOT} || true
cryptsetup luksClose ${_ENCRYPTED_VOLUME_PATH} || true
echo_debug "Partitioning SD Card"
parted ${_OUTPUT_BLOCK_DEVICE} --script -- mklabel msdos
parted ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary fat32 0 256
parted ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary 256 -1
sync

# Create LUKS
echo_debug "Attempting to create LUKS ${_BLOCK_DEVICE_ROOT} "
echo "${_LUKS_PASSWORD}" | cryptsetup -v --cipher ${_LUKS_CONFIGURATION} luksFormat ${_BLOCK_DEVICE_ROOT}
echo_debug "LUKS created ${_BLOCK_DEVICE_ROOT} "

echo_debug "Attempting to open LUKS ${_BLOCK_DEVICE_ROOT} "
echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_BLOCK_DEVICE_ROOT} ${_ENCRYPTED_VOLUME_PATH}
echo_debug "- LUKS open"

make_filesystem "vfat" "${_BLOCK_DEVICE_BOOT}"
make_filesystem "${fs_type}" "${_ENCRYPTED_VOLUME_PATH}"

# Mount LUKS
echo_debug "Mounting ${_ENCRYPTED_VOLUME_PATH} to ${_CHROOT_ROOT}"
mkdir ${_CHROOT_ROOT}
mount ${_ENCRYPTED_VOLUME_PATH} ${_CHROOT_ROOT} && echo_debug "- Mounted ${_ENCRYPTED_VOLUME_PATH} to ${_CHROOT_ROOT}"

# Mount boot partition
echo_debug "Attempting to mount ${_BLOCK_DEVICE_BOOT} to ${_CHROOT_ROOT}/boot "
mkdir ${_CHROOT_ROOT}/boot

mount ${_BLOCK_DEVICE_BOOT} ${_CHROOT_ROOT}/boot && echo_debug "- Mounted ${_BLOCK_DEVICE_BOOT} to ${_CHROOT_ROOT}/boot"

# Attempt to copy files from build to mounted device
rsync_local "${_BUILD_DIR}/mount" "${_CHROOT_ROOT}"
chroot_mount
chroot_mkinitramfs
chroot_umount || true
unmount_block_device ${_BLOCK_DEVICE_BOOT} || true
unmount_block_device ${_BLOCK_DEVICE_ROOT} || true

# Close LUKS
cryptsetup -v luksClose "${_ENCRYPTED_VOLUME_PATH}" | echo_debug "Closing LUKS ${_BLOCK_DEVICE_ROOT}"

# Clean up
rm -r ${_CHROOT_ROOT}
sync
