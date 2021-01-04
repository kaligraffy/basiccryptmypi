#!/bin/sh

  export PATH='/sbin:/bin/:/usr/sbin:/usr/bin'

  while true
  do
      test -e ENCRYPTED_VOLUME_PATH && break || cryptsetup luksOpen ENCRYPTED_VOLUME_PATH
  done

  /scripts/local-top/cryptroot
  for i in $(ps aux | grep 'cryptroot' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
  for i in $(ps aux | grep 'askpass' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
  for i in $(ps aux | grep 'ask-for-password' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
  for i in $(ps aux | grep '\\-sh' | grep -v 'grep' | awk '{print $1}'); do kill -9 $i; done
  exit 0
