#!/bin/bash
set -e

echo_debug "Partitioning SD Card"
parted ${_BLKDEV} --script -- mklabel msdos
parted ${_BLKDEV} --script -- mkpart primary fat32 0 256
parted ${_BLKDEV} --script -- mkpart primary 256 -1
sync

# Create LUKS
echo_debug "Attempting to create LUKS ${_BLKDEV}${_PARTITIONPREFIX}2 "
echo "${_LUKSPASSWD}" | cryptsetup -v --cipher ${_LUKSCIPHER} luksFormat ${_BLKDEV}${_PARTITIONPREFIX}2
echo_debug "LUKS created ${_BLKDEV}${_PARTITIONPREFIX}2 "

echo_debug "Attempting to open LUKS ${_BLKDEV}${_PARTITIONPREFIX}2 "
echo "${_LUKSPASSWD}" | cryptsetup -v luksOpen ${_BLKDEV}${_PARTITIONPREFIX}2 ${_ENCRYPTED_VOLUME_NAME}
echo_debug "- LUKS open"

FS=$_FILESYSTEM_TYPE

# Format
echo_debug "Formatting /dev/mapper/${_ENCRYPTED_VOLUME_NAME}"
mkfs.$FS /dev/mapper/${_ENCRYPTED_VOLUME_NAME}
echo_debug "- Formatted"

# Format boot partition
echo_debug "Formatting Boot Partition"
mkfs.vfat ${_BLKDEV}${_PARTITIONPREFIX}1

# Mount LUKS
echo_debug "Mounting /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"
mkdir /mnt/cryptmypi
mount /dev/mapper/${_ENCRYPTED_VOLUME_NAME} /mnt/cryptmypi && echo_debug "- Mounted /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"

# Mount boot partition
echo_debug "Attempting to mount ${_BLKDEV}${_PARTITIONPREFIX}1 to /mnt/cryptmypi/boot "
mkdir /mnt/cryptmypi/boot

mount ${_BLKDEV}${_PARTITIONPREFIX}1 /mnt/cryptmypi/boot && echo_debug "- Mounted ${_BLKDEV}${_PARTITIONPREFIX}1 to /mnt/cryptmypi/boot"
