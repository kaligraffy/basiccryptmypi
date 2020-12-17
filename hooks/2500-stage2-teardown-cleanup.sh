#!/bin/bash
set -e
set -u

echo_debug "Attempt to unmount just to be safe "
umount ${_OUTPUT_BLOCK_DEVICE}* || true
umount /mnt/cryptmypi || {
    umount -l /mnt/cryptmypi || true
    umount -f ${_ENCRYPTED_VOLUME_PATH} || true
}

[ -d /mnt/cryptmypi ] && rm -r /mnt/cryptmypi || true
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

FS=$_FILESYSTEM_TYPE

# Format
echo_debug "Formatting ${_ENCRYPTED_VOLUME_PATH}"
mkfs.$FS ${_ENCRYPTED_VOLUME_PATH}
echo_debug "- Formatted"

# Format boot partition
echo_debug "Formatting Boot Partition"
mkfs.vfat ${_BLOCK_DEVICE_BOOT}

# Mount LUKS
echo_debug "Mounting ${_ENCRYPTED_VOLUME_PATH} to /mnt/cryptmypi"
mkdir /mnt/cryptmypi
mount ${_ENCRYPTED_VOLUME_PATH} /mnt/cryptmypi && echo_debug "- Mounted ${_ENCRYPTED_VOLUME_PATH} to /mnt/cryptmypi"

# Mount boot partition
echo_debug "Attempting to mount ${_BLOCK_DEVICE_BOOT} to /mnt/cryptmypi/boot "
mkdir /mnt/cryptmypi/boot

mount ${_BLOCK_DEVICE_BOOT} /mnt/cryptmypi/boot && echo_debug "- Mounted ${_BLOCK_DEVICE_BOOT} to /mnt/cryptmypi/boot"
# Attempt to copy files from build to mounted device
echo_debug "Syncing build to disk"
echo_info "Starting copy of build to ${_CHROOT_ROOT} at $(date)"
rsync \
    --hard-links \
    --archive \
    --verbose \
    --partial \
    --progress \
    --quiet \
    --info=progress2 "${_BUILD_DIR}/mount/"* "${_CHROOT_ROOT}"

# Sync file system
echo_debug "Syncing the filesystems ."
sync

chroot_mount
chroot_mkinitramfs

chroot_umount || true

unmount_block_device ${_BLOCK_DEVICE_BOOT} 
unmount_block_device ${_BLOCK_DEVICE_ROOT}

# Close LUKS
echo_debug "Closing LUKS ${_BLOCK_DEVICE_ROOT}"
cryptsetup -v luksClose "${_ENCRYPTED_VOLUME_PATH}"

# Clean up
rm -r /mnt/cryptmypi
sync
