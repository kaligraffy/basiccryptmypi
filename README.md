# basic_cryptmypi
basic_cryptmypi - A really simple pi deployment script.

With thanks to unixabg for the original script.

PURPOSE

Creates a configurable sd card or disk image for the raspberry pi with strong encryption as default with kali or pios

Supports 64/32 bit, kali and pios

USAGE

Leave aside about 20GB of space for this for the kali image, about 5G for pios if using image mode

Usage: 

rename an env.sh example to env.sh and modify variables

sudo ./cryptmypi.sh ARG1

ARG1 can be:
-b or build - standard build
-m or mount_only - only mount an image or disk
-u or unmount - unmount
-i or install - install dependencies
-mk or mkinitramfs - mounts and runs the mkinitramfs
-h or help - prints this help message
Follow the prompts

ISSUES

- chroot commands aren't necessarily raising errors when they error!

LOGGING

The script logs to the cryptmypi directory file build.log
