#!/bin/bash
set -e

FS=$_FILESYSTEM

# Format
echo_debug "Formatting /dev/mapper/${_ENCRYPTED_VOLUME_NAME}"
case $FS in
"ext4"|"btrfs")       
    mkfs.$FS /dev/mapper/${_ENCRYPTED_VOLUME_NAME}
    echo_debug "- Formatted"
    ;;          
*) echo "Filesystem not detected"; exit 1;             
esac 

# Format boot partition
echo_debug "Formatting Boot Partition"
mkfs.vfat ${_BLKDEV}${__PARTITIONPREFIX}1
echo
