#!/bin/bash
set -e
set -u

# REFERENCE:
#   https://davidhamann.de/2019/05/12/tunnel-traffic-over-dns-ssh/
echo_debug "Attempting iodine"
chroot_pkginstall install iodine

# Create initramfs hook file for iodine
cat << 'EOF2' > ${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-iodine
#!/bin/sh
if [ "$1" = "prereqs" ]; then exit 0; fi
. /usr/share/initramfs-tools/hook-functions

copy_exec "/usr/sbin/iodine"

#we need a tun device for iodine
manual_add_modules tun

#Generate Script that runs in initramfs
cat > ${DESTDIR}/start_iodine << 'EOF'
#!/bin/sh

echo "Starting Iodine"
busybox modprobe tun
counter=1

while true; do
    echo Try $counter: $(date)

    #exit if we are no longer in the initramfs
    [ ! -f /start_iodine ] && exit

    #put this here in case it dies, it will restart. If it is running it will just fail
    /usr/sbin/iodine -d dns0 -r -I1 -L0 -P IODINE_PASSWORD $(grep IPV4DNS0 /run/net-eth0.conf | cut -d"'" -f 2) IODINE_DOMAIN

    [ $counter -gt 10 ] && reboot -f
    counter=$((counter+1))
    sleep 60
done;
EOF
chmod 755 ${DESTDIR}/start_iodine

exit 0
EOF2
chmod 755 ${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-iodine

# Replace variables in iodine hook file
sed -i "s#IODINE_PASSWORD#${_IODINE_PASSWORD}#g" ${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-iodine
sed -i "s#IODINE_DOMAIN#${_IODINE_DOMAIN}#g" ${_CHROOT_ROOT}/etc/initramfs-tools/hooks/zz-iodine

# Create initramfs script file for iodine
cat << 'EOF' > ${_CHROOT_ROOT}/etc/initramfs-tools/scripts/init-premount/iodine
#!/bin/sh
if [ "$1" = "prereqs" ]; then exit 0; fi
startIodine(){
    exec /start_iodine
}
startIodine &
exit 0
EOF
chmod 755 ${_CHROOT_ROOT}/etc/initramfs-tools/scripts/init-premount/iodine

echo_debug " iodine call completed"
