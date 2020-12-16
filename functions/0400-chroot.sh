#!/bin/bash
set -e

chroot_mount(){

    echo_debug "Preparing RPi chroot mount structure at '${_CHROOT_ROOT}'."
    [ -z "${_CHROOT_ROOT}" ] && {
        echo_error "Chroot dir was not defined! Aborting..."
        exit 1
    }

    # mount binds
    echo_debug "Mounting '${_CHROOT_ROOT}/dev/' ..."
    mount --bind /dev ${_CHROOT_ROOT}/dev/ || echo_error "ERROR while mounting '${_CHROOT_ROOT}/dev/'"
    echo_debug "Mounting '${_CHROOT_ROOT}/dev/pts' ..."
    mount --bind /dev/pts ${_CHROOT_ROOT}/dev/pts || echo_error "ERROR while mounting '${_CHROOT_ROOT}/dev/pts'"
    echo_debug "Mounting '${_CHROOT_ROOT}/sys/' ..."
    mount --bind /sys ${_CHROOT_ROOT}/sys/ || echo_error "ERROR while mounting '${_CHROOT_ROOT}/sys/'"
    echo_debug "Mounting '${_CHROOT_ROOT}/proc/' ..."
    mount -t proc /proc ${_CHROOT_ROOT}/proc/ || echo_error "ERROR while mounting '${_CHROOT_ROOT}/proc/'"

#    # ld.so.preload fix
#    test -e ${_CHROOT_ROOT}/etc/ld.so.preload && {
#        echo_debug "Fixing ld.so.preload"
#        sed -i 's/^/#CHROOT /g' ${_CHROOT_ROOT}/etc/ld.so.preload
#    } || true
}


chroot_umount(){
    [ -z "${_CHROOT_ROOT}" ] && {
        exit 1
    }
    echo_debug "Tearing down RPi chroot mount structure at '${_CHROOT_ROOT}'."

#    # revert ld.so.preload fix
#    test -e ${_CHROOT_ROOT}/etc/ld.so.preload && {
#        echo_debug "Reverting ld.so.preload fix"
#        sed -i 's/^#CHROOT //g' ${_CHROOT_ROOT}/etc/ld.so.preload
#    } || true

    # unmount everything
    echo_debug "Unmounting binds"
    umount ${_CHROOT_ROOT}/{dev/pts,dev,sys,proc}

    export _CHROOT_ROOT=''
}


chroot_update(){
    [ -z "${_CHROOT_ROOT}" ] && {
        echo_error "Chroot dir was not defined! Aborting..."
        exit 1
    }
    
    #Force https on initial use of apt for the main kali repo
    sed -i 's|http:|https:|g' ${_CHROOT_ROOT}/etc/apt/sources.list
    
    if [ -f "${_CHROOT_ROOT}/etc/resolv.conf" ]; then
        echo_debug "${_CHROOT_ROOT}/etc/resolv.conf exists."
    else
        echo_warn "${_CHROOT_ROOT}/etc/resolv.conf does not exists."
        echo_warn "Setting nameserver to $_DNS1 and $_DNS2 in ${_CHROOT_ROOT}/etc/resolv.conf"
        echo -e "nameserver $_DNS1\nnameserver $_DNS2" > "${_CHROOT_ROOT}/etc/resolv.conf"
    fi

    echo_debug "Updating apt-get"
    chroot ${_CHROOT_ROOT} apt-get update
}

chroot_pkginstall(){
    [ -z "${_CHROOT_ROOT}" ] && {
        echo_error "Chroot dir was not defined! Aborting..."
        exit 1
    }

    if [ ! -z "$1" ]; then
        for param in "$@"; do
            for pkg in $param; do
                echo_debug "- Installing ${pkg}"
                chroot ${_CHROOT_ROOT} apt-get -qq install "${pkg}" || {
                    echo_warn "apt-get failed: Trying to recover..."
                    chroot ${_CHROOT_ROOT} /bin/bash -x <<EOF
                        sleep 5
                        apt-get update
                        apt-get -qq install "${pkg}" || exit 1
EOF
                    status=$?
                    [ $status -eq 0 ] || {
                        echo_error "ERROR: Could not install ${pkg} correctly... Exiting.";
                        exit 1
                    }
                }
            done
        done
    fi
}


chroot_pkgpurge(){
    [ -z "${_CHROOT_ROOT}" ] && {
        echo_error "Chroot dir was not defined! Aborting..."
        exit 1
    }

    if [ ! -z "$1" ]; then
        for param in "$@"; do
            for pkg in $param; do
                echo_debug "- Purging ${pkg}"
                chroot ${_CHROOT_ROOT} apt-get -y purge "${pkg}"
            done
        done
        chroot ${_CHROOT_ROOT} apt-get -y autoremove
    fi
}


chroot_execute(){
    [ -z "${_CHROOT_ROOT}" ] && {
        echo_error "Chroot dir was not defined! Aborting..."
        exit 1
    }

    chroot ${_CHROOT_ROOT} "$@"
}


chroot_mkinitramfs(){
    echo_debug "Attempting to build new initramfs ... (CHROOT is ${_CHROOT_ROOT})"

    # crypttab needs to point to the current physical device during mkinitramfs or cryptsetup won't deploy
    echo_debug "  Creating symbolic links from current physical device to crypttab device (if not using sd card mmcblk0p)"
    test -e "/dev/mmcblk0p1" || (test -e "/${_BLKDEV}1" && ln -s "/${_BLKDEV}1" "/dev/mmcblk0p1")
    test -e "/dev/mmcblk0p2" || (test -e "/${_BLKDEV}2" && ln -s "/${_BLKDEV}2" "/dev/mmcblk0p2")

    # determining the kernel
    _KERNEL_VERSION=$(ls ${_CHROOT_ROOT}/lib/modules/ | grep "${_KERNEL_VERSION_FILTER}" | tail -n 1)
    echo_debug "  Using kernel '${_KERNEL_VERSION}'"
    chroot_execute update-initramfs -u -k all
    # Finally, Create the initramfs
    echo_debug "  Building new initramfs ..."
    chroot_execute mkinitramfs -o /boot/initramfs.gz -v ${_KERNEL_VERSION}

    # cleanup
    echo_debug "  Cleaning up symbolic links"
    test -L "/dev/mmcblk0p1" && unlink "/dev/mmcblk0p1"
    test -L "/dev/mmcblk0p2" && unlink "/dev/mmcblk0p2"
}
