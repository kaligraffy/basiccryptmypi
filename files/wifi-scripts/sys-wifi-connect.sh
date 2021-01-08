#!/bin/bash

# Remove file if exists
test -e /var/run/wpa_supplicant/wlan0 && rm -f /var/run/wpa_supplicant/wlan0

# Power interface up
ip link set _WIFI_INTERFACE down
ip link set _WIFI_INTERFACE up

# Connect to WPA WiFi network
wpa_supplicant -B -Dwext -i _WIFI_INTERFACE -c /etc/wpa_supplicant.conf

# Get IP from dhcp
dhclient _WIFI_INTERFACE
