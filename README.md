# basic_cryptmypi

With thanks to unixabg for the original script.

PURPOSE

A  pi deployment script for making an encrypted pi with kali, pios and possibly debian. 
Supports 64/32 bit

USAGE

1. Leave aside about 20GB of space for this for the kali image, about 5G for pios if using image mode
2. Rename an env.sh-example file to 'env.sh' in the project directory and amend the variables to your specification.
There is quite a few that can be altered, and more in functions.sh which can be overwritten by env.sh

3. sudo ./cryptmypi.sh ARG1

ARG1 can be:
-b or build - standard build 
-m or mount- only mount an image or disk
-u or unmount - unmount
-i or install - install dependencies
-mk or mkinitramfs - mounts and runs the mkinitramfs
-h or help - prints this help message
Follow the prompts

ISSUES

- chroot commands aren't necessarily raising errors when they error, most do however
- debian not working yet
- locale generation is working, but there are warnings raised when ran

LOGGING

The script logs to the cryptmypi directory file build.log. This is overwritten each build.
