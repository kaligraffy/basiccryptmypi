#!/bin/bash
set -e


# REFERENCE:
#   https://davidhamann.de/2019/05/12/tunnel-traffic-over-dns-ssh/


echo_debug "Attempting iodine "

chroot_pkginstall install iodine

# Create iodine startup script (not initramfs)
    cat << EOF > ${_CHROOT_ROOT}/opt/iodine.sh
#!/bin/bash
while true; do
    iodine -f -r -I1 -L0 -P ${_IODINE_PASSWORD} ${_IODINE_DOMAIN}
    sleep 60
done
EOF
chmod 755 ${_CHROOT_ROOT}/opt/iodine.sh

cat << EOF > ${_CHROOT_ROOT}/crontab_setup
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
@reboot /opt/iodine.sh
EOF
chroot_execute crontab /crontab_setup
rm ${_CHROOT_ROOT}/crontab_setup

echo_debug "iodine call complete"
