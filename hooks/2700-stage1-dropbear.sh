#!/bin/bash
set -e


echo_debug "Attempting to install dropbear ..."


if [ -z "${_SSH_LOCAL_KEYFILE}" ]; then
    echo_error "ERROR: _SSH_LOCAL_KEYFILE variable was not set. Exiting..."
    exit 1
else
    test -f "${_SSH_LOCAL_KEYFILE}" || {
        echo_error "ERROR: Obligatory SSH keyfile '${_SSH_LOCAL_KEYFILE}' could not be found. Exiting..."
        exit 1
    }
fi


# Installing packages
chroot_pkginstall dropbear dropbear-initramfs cryptsetup-initramfs

echo 'DROPBEAR_OPTIONS="-p 2222 -RFEjk -c /bin/cryptroot-unlock"' > ${_CHROOT_ROOT}/etc/dropbear-initramfs/config

#REMOVED .TMP AUTH KEYS CODE HERE.
# Now append our key to dropbear authorized_keys file
cat "${_SSH_LOCAL_KEYFILE}.pub" >> ${_CHROOT_ROOT}/etc/dropbear-initramfs/authorized_keys
chmod 600 ${_CHROOT_ROOT}/etc/dropbear-initramfs/authorized_keys


# Update dropbear for some sleep in initramfs
sed -i 's#run_dropbear \&#sleep 5\nrun_dropbear \&#g' ${_CHROOT_ROOT}/usr/share/initramfs-tools/scripts/init-premount/dropbear

# Using provided dropbear keys (or backuping generating ones for later usage)
#backup_and_use_sshkey ${_CHROOT_ROOT}/etc/dropbear-initramfs/dropbear_dss_host_key
#backup_and_use_sshkey ${_CHROOT_ROOT}/etc/dropbear-initramfs/dropbear_ecdsa_host_key
backup_and_use_sshkey ${_CHROOT_ROOT}/etc/dropbear-initramfs/dropbear_rsa_host_key


echo_debug "... dropbearpi call completed!"
