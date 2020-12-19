#!/bin/bash
set -eu

encryption_setup(){
  echo_info "$FUNCNAME started at $(date) ";
  
  # Check if btrfs is the file system, if so install required packages
  fs_type="${_FILESYSTEM_TYPE}"
  if [ "$fs_type" = "btrfs" ]; then
      echo_debug "- Setting up btrfs-progs on build machine"
      apt-get -qq install btrfs-progs
      echo_debug "- Setting up btrfs-progs in chroot"
      chroot_package_install "${_CHROOT_ROOT}" btrfs-progs
      echo_debug "- Adding btrfs module to initramfs-tools/modules"
      echo 'btrfs' >> ${_CHROOT_ROOT}/etc/initramfs-tools/modules
  fi

  # Setup qemu emulator for aarch64
  echo_debug "- Copying qemu emulator to chroot "
  cp /usr/bin/qemu-aarch64-static ${_CHROOT_ROOT}/usr/bin/
  chroot_package_install "${_CHROOT_ROOT}" cryptsetup busybox

  # Creating symbolic link to e2fsck
  chroot ${_CHROOT_ROOT} /bin/bash -c "test -L /sbin/fsck.luks || ln -s /sbin/e2fsck /sbin/fsck.luks"

  # Indicate kernel to use initramfs (facilitates loading drivers)
  echo "initramfs initramfs.gz followkernel" >> ${_CHROOT_ROOT}/boot/config.txt

  # Begin cryptsetup
  echo_debug "Making the cryptsetup settings "

  # Update /boot/cmdline.txt to boot crypt
  sed -i "s|root=/dev/mmcblk0p2|root=${_ENCRYPTED_VOLUME_PATH} cryptdevice=/dev/mmcblk0p2:${_ENCRYPTED_VOLUME_PATH}|g" ${_CHROOT_ROOT}/boot/cmdline.txt
    sed -i "s|rootfstype=ext3|rootfstype=${fs_type}|g" ${_CHROOT_ROOT}/boot/cmdline.txt

    # Enable cryptsetup when building initramfs
    echo "CRYPTSETUP=y" >> ${_CHROOT_ROOT}/etc/cryptsetup-initramfs/conf-hook

    # Update /etc/fstab
    sed -i "s|/dev/mmcblk0p2|${_ENCRYPTED_VOLUME_PATH}|g" ${_CHROOT_ROOT}/etc/fstab
    sed -i "s#ext3#${fs_type}#g" ${_CHROOT_ROOT}/etc/fstab

    # Update /etc/crypttab
    echo "${_ENCRYPTED_VOLUME_PATH}    /dev/mmcblk0p2    none    luks" > ${_CHROOT_ROOT}/etc/crypttab

    # Create a hook to include our crypttab in the initramfs
    cat << EOF > ${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-cryptsetup
    # !/bin/sh
    set -e

    PREREQ=""
    prereqs()
    {
        echo "\${PREREQ}"
    }

    case "\${1}" in
        prereqs)
            prereqs
            exit 0
            ;;
    esac

    . /usr/share/initramfs-tools/hook-functions

    mkdir -p \${DESTDIR}/cryptroot || true
    cat /etc/crypttab >> \${DESTDIR}/cryptroot/crypttab
    cat /etc/fstab >> \${DESTDIR}/cryptroot/fstab
    cat /etc/crypttab >> \${DESTDIR}/etc/crypttab
    cat /etc/fstab >> \${DESTDIR}/etc/fstab
    copy_file config /etc/initramfs-tools/unlock.sh /etc/unlock.sh
EOF
    chmod 755 ${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-cryptsetup

    # Unlock Script
    cat << EOF > "${_CHROOT_ROOT}/etc/initramfs-tools/unlock.sh"
    #!/bin/sh

    export PATH='/sbin:/bin/:/usr/sbin:/usr/bin'

    while true
    do
        test -e ${_ENCRYPTED_VOLUME_PATH} && break || cryptsetup luksOpen /dev/mmcblk0p2
    done

    /scripts/local-top/cryptroot
    for i in \$(ps aux | grep 'cryptroot' | grep -v 'grep' | awk '{print \$1}'); do kill -9 \$i; done
    for i in \$(ps aux | grep 'askpass' | grep -v 'grep' | awk '{print \$1}'); do kill -9 \$i; done
    for i in \$(ps aux | grep 'ask-for-password' | grep -v 'grep' | awk '{print \$1}'); do kill -9 \$i; done
    for i in \$(ps aux | grep '\\-sh' | grep -v 'grep' | awk '{print \$1}'); do kill -9 \$i; done
    exit 0
EOF
    chmod +x "${_CHROOT_ROOT}/etc/initramfs-tools/unlock.sh"

    # Adding dm_mod to initramfs modules
    echo 'dm_crypt' >> ${_CHROOT_ROOT}/etc/initramfs-tools/modules

    # Disable autoresize
    chroot_execute "${_CHROOT_ROOT}" systemctl disable rpiwiggle
}
encryption_setup
