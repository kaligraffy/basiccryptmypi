# basiccryptmypi
basiccryptmypi - A really simple kali pi build script to make an encrypted RPi 4. With thanks to unixabg for the original script.

THIS IS A WORK IN PROGRESS, DON'T DOWNLOAD UNLESS YOU ARE PREPARED TO TROUBLESHOOT

USAGE

Leave aside about 30GB of disk space 

Modify .env with your settings. At the least change:
export _OUTPUT_BLOCK_DEVICE="/dev/sdX"
export _LUKS_PASSWORD="CHANGEME"
export _ROOT_PASSWORD="CHANGEME"
export _KALI_PASSWORD="CHANGEME"
export _SSH_KEY_PASSPHRASE="CHANGEME"
export _WIFI_PASSWORD='CHANGEME'
export _IMAGE_SHA256="c6ceee472eb4dabf4ea895ef53c7bd28751feb44d46ce2fa3f51eb5469164c2c"
export _IMAGE_URL="https://images.kali.org/arm-images/kali-linux-2020.4-rpi4-nexmon-64.img.xz"

Un/Comment anything in function extra_setup() you want to use.

Run: 
- change directory to cryptmypi directory
- sudo ./cryptmypi
- follow prompts

PURPOSE

Creates a configurable kali sd card or usb for the raspberry pi with strong encryption as default as well as other functionality as default.
Its meant to provide reasonable defaults if you have a rpi4 and be really easy to use and debug

This was based on an original project to make a headless kali pi build script and other things,
 the hope is to expand on that by providing simple config,
 clean up some of the code, thoroughly test it and then 
 attempt to build an image from scratch later on down the line,
  perhaps against non-kali images


This includes:
- btrfs filesystem
- strong luks encryption
- DNSSEC enabled by default
- DNSoverHTTPS enabled by default
- ssh on port 2222 with key or password-based encryption
- dropbear on port 2222 with key or password-based encryption
- antivirus
- basic firewall
- aide intrusion protection
- a fake hardware clock
- ntpsec (more secure than ntp)
- luks nuke
- a script to hash your boot and mail you if it changes

Testing is 'ad hoc' and only for the rpi 4. In theory it should still work with rpi3 if you set the right kernel in env.sh

ISSUES

Occasionally, the mounts don't get cleaned up properly, if this is the case run: losetup -D; umount /dev/loop/*; mount
Then check if there are any other mounts to umount.

TODO
- re-comment the .env file for the less obvious environment variables
- use BATS to test the script
- TEST initramfs wifi, ssh and dropbear work together
- SSH defaults
- sysctl hardening against lynis
- apparmor/firejail support
- passwordless login (after decryption)
- incorrect fstab settings for btrfs (last digit should be 0 for no fsck (tbc)
- no assessment of noload being taken out of cmdline.txt for ext4 filesystems (may cause additional writes
- duplicate entries in crypttab in the initramfs by script
- clean up folders logic may not be working, sometimes the build folder remains if cleared
- fix unmount logic

HOW DOES IT WORK

1. The script downloads the image using the URL specified in the .env file (if it's already there it skips downloading it)
2. Then it extracts the image (if it's already there it asks if you want to re-extract)
3. Then it copies the contents to a directory called 'root' in the build directory
4. Then it runs the normal configuration 
5. Then it runs the custom configuration specified in .env (in function extra_setup)
6. Finally, it creates an encrypted disk and writes the build to it

LOGGING

The script logs to the cryptmypi directory, making a log of all actions to the file specified in the .env file.
