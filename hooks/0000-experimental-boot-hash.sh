#!/bin/bash
set -e

#install mail package
chroot_package_install mailutils

BOOTDRIVE="${_OUTPUT_BLOCK_DEVICE}${_PARTITIONPREFIX}1"
BOOTHASHSCRIPT="${_CHROOT_ROOT}/usr/local/bin/bootHash.sh"
echo_debug "Creating script bootHash.sh in ${_BUILDDIR}/usr/local/bin"

cat << 'EOF' > "$BOOTHASHSCRIPT"
#!/bin/bash
#user to be mailed (kali, root)
MAILUSER=kali
#boot device mmcblk0p1 or /dev/sda1
BOOTDRIVE=/dev/sdX
LOGFILE="/var/log/$BOOTDRIVE-hashes"
LASTHASH=$(tail -1 $LOGFILE)
NEWHASH="$(sha256sum $BOOTDRIVE) $(date)"
echo $NEWHASH >> "$LOGFILE"

LASTHASH=$(echo "$LASTHASH" | cut -d' ' -f 1)
NEWHASH=$(echo "$NEWHASH" | cut -d' ' -f 1)

if [ "$LASTHASH" != "$NEWHASH" ]; then
    echo -e "${NEWHASH}\n${LASTHASH}" | mail -s "BOOT HASH CHANGE" $MAILUSER
fi
EOF

sed -i "s|/dev/sdX|${BOOTDRIVE}|g" "$BOOTHASHSCRIPT"
chmod 700 "$BOOTHASHSCRIPT"

#crontab run on startup
cat << 'EOF' > ${_CHROOT_ROOT}/etc/cron.d/startBootHash
@reboot root /bin/bash /usr/local/bin/bootHash.sh
EOF
chmod 755 ${_CHROOT_ROOT}/etc/cron.d/startBootHash
