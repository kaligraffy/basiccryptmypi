#!/bin/sh
# shellcheck disable=SC2086
# shellcheck disable=SC2009
set -eu
export PATH='/sbin:/bin/:/usr/sbin:/usr/bin'

#Adapted from Raphael Hertzog's script at https://gitlab.com/kalilinux/packages/cryptsetup-nuke-password/-/blob/kali/master/askpass
#and maloman's script https://serverfault.com/questions/714605/can-cryptsetup-read-mappings-from-etc-crypttab
#Used by dropbear-initramfs
#implements luks nuke support (there's a bug in cryptroot/askpass when being called from a dropbear login over wifi)

CRYPTTAB_SOURCE=ENCRYPTED_VOLUME_PATH
NUKE_PASSWORD_HASH_PATH=${NUKE_PASSWORD_HASH_PATH:-/etc/cryptsetup-nuke-password/password_hash}
CRYPT_HELPER=${CRYPT_HELPER:-/usr/lib/cryptsetup-nuke-password/crypt}

sanity_checks() {
    local cryptsetup="$(which cryptsetup 2>/dev/null)"
    if [ -z "$cryptsetup" ]; then
	echo "$0: WARNING: cryptsetup not found in PATH" >&2
	return 1
    fi
    if [ ! -e "$CRYPTTAB_SOURCE" ]; then
	echo "$0: WARNING: \$CRYPTTAB_SOURCE (value: $CRYPTTAB_SOURCE) does not exist" >&2
	return 1
    fi
    if [ ! -x "$CRYPT_HELPER" ]; then
	echo "$0: WARNING: $CRYPT_HELPER is not executable" >&2
	return 1
    fi
    return 0
}

hash_is_matching() {
    local pass="$1"
    local pass_hash

    if [ ! -r $NUKE_PASSWORD_HASH_PATH ]; then
	# No hash, no match
	return 1
    fi
    pass_hash=$(cat $NUKE_PASSWORD_HASH_PATH)
    if echo -n "$pass" | $CRYPT_HELPER --check "$pass_hash"; then
	# User typed the nuke password!
	return 0
    else
	return 1
    fi
}

nuke_cryptsetup_partition() {
    local partition="$1"
    cryptsetup --batch-mode erase "$partition"
}

#GET FIRST AND SECOND ARGUMENTS
ENCRYPTED_DEV=$(grep -w $CRYPTTAB_SOURCE /etc/crypttab)
SEC_FIELD=$(echo $ENCRYPTED_DEV | sed -r 's/\s+/ /g' | cut -d' ' -f2)

while true
do
    stty -echo
    read -p "Please unlock $CRYPTTAB_SOURCE: " PASSWORD

    if sanity_checks && hash_is_matching "$PASSWORD"; then
        nuke_cryptsetup_partition "$CRYPTTAB_SOURCE"
    fi

    echo "$PASSWORD" | cryptsetup luksOpen $SEC_FIELD $CRYPTTAB_SOURCE
done
exit 0

#/scripts/local-top/cryptroot
#for i in $(ps aux | grep 'cryptroot' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
#for i in $(ps aux | grep 'askpass' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
#for i in $(ps aux | grep 'ask-for-password' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
#for i in $(ps aux | grep '\\-sh' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
