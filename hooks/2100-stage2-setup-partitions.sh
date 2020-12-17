#!/bin/bash
set -e

echo_debug "Partitioning SD Card"
parted ${_OUTPUT_BLOCK_DEVICE} --script -- mklabel msdos
parted ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary fat32 0 256
parted ${_OUTPUT_BLOCK_DEVICE} --script -- mkpart primary 256 -1
sync

# Create LUKS
echo_debug "Attempting to create LUKS ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}2 "
echo "${_LUKS_PASSWORD}" | cryptsetup -v --cipher ${_LUKS_CONFIGURATION} luksFormat ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}2
echo_debug "LUKS created ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}2 "

echo_debug "Attempting to open LUKS ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}2 "
echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}2 ${_ENCRYPTED_VOLUME_NAME}
echo_debug "- LUKS open"

FS=$_FILESYSTEM_TYPE

# Format
echo_debug "Formatting /dev/mapper/${_ENCRYPTED_VOLUME_NAME}"
mkfs.$FS /dev/mapper/${_ENCRYPTED_VOLUME_NAME}
echo_debug "- Formatted"

# Format boot partition
echo_debug "Formatting Boot Partition"
mkfs.vfat ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}1

# Mount LUKS
echo_debug "Mounting /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"
mkdir /mnt/cryptmypi
mount /dev/mapper/${_ENCRYPTED_VOLUME_NAME} /mnt/cryptmypi && echo_debug "- Mounted /dev/mapper/${_ENCRYPTED_VOLUME_NAME} to /mnt/cryptmypi"

# Mount boot partition
echo_debug "Attempting to mount ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}1 to /mnt/cryptmypi/boot "
mkdir /mnt/cryptmypi/boot

mount ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}1 /mnt/cryptmypi/boot && echo_debug "- Mounted ${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}1 to /mnt/cryptmypi/boot"
