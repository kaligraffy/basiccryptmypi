#!/bin/bash
#user to be mailed (kali, root)

MAILUSER=kali;
#boot device mmcblk0p1 or /dev/sda1
BOOTDRIVE=/dev/sdX;
LOGFILE="/var/log/$BOOTDRIVE-hashes";
LASTHASH=$(tail -1 $LOGFILE);
NEWHASH="$(sha256sum $BOOTDRIVE) $(date)";
echo $NEWHASH >> "$LOGFILE";

LASTHASH=$(echo "$LASTHASH" | cut -d' ' -f 1);
NEWHASH=$(echo "$NEWHASH" | cut -d' ' -f 1);

if [ "$LASTHASH" != "$NEWHASH" ]; then
    echo -e "${NEWHASH}\n${LASTHASH}" | mail -s "BOOT HASH CHANGE" $MAILUSER;
fi
exit;
