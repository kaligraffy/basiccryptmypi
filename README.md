# basiccryptmypi
basiccryptmypi - A really simple kali pi build script to make an encrypted RPi 4. With thanks to unixabg for the original script.

USAGE

Leave aside about 30GB of disk space 

Modify .env with your settings. 
- Change any password field 
- Update the image url if it's changed, and you want the most recent kali pi image
- Call any optional 'hooks' in prepare_image_extras
- And the disk e.g /dev/sda or /dev/mmcblk1

Run: 
- change directory to cryptmypi directory
- sudo ./cryptmypi

PURPOSE

Creates a configurable kali sd card or usb for the raspberry pi with strong encryption as default as well as other functionality as default.
Its meant to provide reasonable defaults if you have a rpi4 and be really easy to use and debug

This includes:
- btrfs filesystem
- strong luks encryption
- ssh on port 2222 with key or password-based encryption
- dropbear on port 2222 with key or password-based encryption

Extra functions (Uncomment in .env file)

- 0000-experimental-boot-hash.sh - a small script which checks the hash of your boot directory on startup and mails the kali user if it changes
- 0000-optional-initramfs-luksnuke.sh - nuke the luks key given a specific character on startup
- 0000-optional-sys-cpu-governor.sh - sets the cpu governor to ondemand or performance (useful if you want to run off a battery)
- 0000-optional-sys-dns.sh - sets dns as per env
- 0000-optional-sys-rootpassword.sh - sets root password
- 0000-experimental-initramfs-wifi.sh - TESTING IN PROGRESS, WIFI ON STARTUP TO ENABLE HEADLESS MODE
- 0000-experimental-sys-iodine.sh - UNTESTED
- 0000-experimental-initramfs-iodine.sh - UNTESTED
- 0000-optional-sys-docker.sh - UNTESTED
- 0000-optional-sys-vpnclient.sh - UNTESTED
- 0000-optional-sys-wifi.sh - UNTESTED

TESTING

Testing is 'ad hoc' and only for the rpi 4. In theory it should still work with rpi3 if you set the right kernel.

ISSUES

Main issues is error handling and the unmount logic at the moment.

Occasionally, the mounts don't get cleaned up properly, if this is the case run: losetup -D; umount /dev/loop/*; mount
Then check if there are any other mounts to umount.

Raise on here and I'll try and fix them as soon as I can, this is a refactor of an existing project, 
I highly anticipate bugs, despite removing a large amount of code which *should* make this more predictable.



TODO

In the future I want to:
- make this work with DNS over TLS or DNS over HTTPS 
- provide a simple firewall script or configure UFW as default
- re-comment the .env file for the less obvious environment variables
- use BATS to test the script

HOW DOES IT WORK

1. The script downloads the image using the URL specified in the .env file (if it's already there it skips downloading it)
2. Then it extracts the image (if it's already there it asks if you want to re-extract)
3. Then it copies the contents to a directory called 'root' in the build directory
4. Then it runs the normal configuration scripts
5. Then it runs the custom configuration scripts specified in .env (in function prepare_image_extras)
6. Finally, it creates an encrypted disk and writes the build to it

LOGGING

The script logs to the build directory, making a log of all actions to the file specified in the .env file.
