# basiccryptmypi
basiccryptmypi - A really simple kali pi build script to make an encrypted RPi 4. With thanks to unixabg for the original script.

USAGE

Leave aside about 30GB of disk space 

Modify .env with your settings. At the least change:
export _OUTPUT_BLOCK_DEVICE="CHANGEME"
export _LUKS_PASSWORD="CHANGEME"
export _ROOT_PASSWORD="CHANGEME"
export _KALI_PASSWORD="CHANGEME"
export _SSH_KEY_PASSPHRASE="CHANGEME"
export _WIFI_PASSWORD='CHANGEME'
export _IMAGE_SHA256="c6ceee472eb4dabf4ea895ef53c7bd28751feb44d46ce2fa3f51eb5469164c2c"
export _IMAGE_URL="https://images.kali.org/arm-images/kali-linux-2020.4-rpi4-nexmon-64.img.xz"

Call any optional 'hooks' in prepare_image_extras (comment/uncomment as necessary):

prepare_image_extras(){
   call_hooks optional-boot-hash
   call_hooks optional-initramfs-luks-nuke
   call_hooks optional-sys-cpu-governor
   call_hooks optional-sys-dns
   call_hooks optional-sys-root-password
   call_hooks optional-sys-kali-password
 #call_hooks optional-ssh
 #call_hooks optional-dropbear
 #call_hooks experimental-initramfs-wifi
   call_hooks optional-ufw
 #call_hooks experimental-sys-iodine
 #call_hooks experimental-initramfs-iodine
 #call_hooks optional-sys-docker
 #call_hooks optional-sys-vpnclient
 #call_hooks optional-sys-wifi
}

Run: 
- change directory to cryptmypi directory
- sudo ./cryptmypi
- follow prompts

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
- 0000-optional-initramfs-luks-nuke.sh - nuke the luks key given a specific character on startup
- 0000-optional-sys-cpu-governor.sh - sets the cpu governor to ondemand or performance (useful if you want to run off a battery)
- 0000-optional-sys-dns.sh - sets dns as per env
- 0000-optional-sys-root-password.sh - sets root password
- 0000-optional-sys-user-password.sh - sets user password
- 0000-experimental-initramfs-wifi.sh - TESTING IN PROGRESS, WIFI ON STARTUP TO ENABLE HEADLESS MODE
- 0000-experimental-sys-iodine.sh - UNTESTED
- 0000-experimental-initramfs-iodine.sh - UNTESTED
- 0000-optional-sys-docker.sh - UNTESTED
- 0000-optional-sys-vpnclient.sh - UNTESTED
- 0000-optional-sys-wifi.sh - UNTESTED
- 0000-optional-sys-ufw.sh - BASIC FIREWALL UNTESTED

TESTING

Testing is 'ad hoc' and only for the rpi 4. In theory it should still work with rpi3 if you set the right kernel in env.sh

ISSUES

- unmount logic

Occasionally, the mounts don't get cleaned up properly, if this is the case run: losetup -D; umount /dev/loop/*; mount
Then check if there are any other mounts to umount.

Raise on here and I'll try and fix them as soon as I can, this is a refactor of an existing project, 
I highly anticipate bugs, despite removing a large amount of code which *should* make this slightly more streamlined

- duplicate entries in crypttab in the initramfs by script

- incorrect fstab settings for btrfs (last digit should be 0 for no fsck (tbc)

- no assessment of noload being taken out of cmdline.txt for ext4 filesystems (may cause additional writes

- initramfs,ssh and dropbear are not tested yet (priority atm)

- clean up folders logic may not be working, sometimes the build folder remains if cleared

TODO

In the future I want to:
- make this work with DNS over TLS or DNS over HTTPS
- re-comment the .env file for the less obvious environment variables
- use BATS to test the script
- make initramfs wifi, ssh and dropbear work together
- 

HOW DOES IT WORK

1. The script downloads the image using the URL specified in the .env file (if it's already there it skips downloading it)
2. Then it extracts the image (if it's already there it asks if you want to re-extract)
3. Then it copies the contents to a directory called 'root' in the build directory
4. Then it runs the normal configuration scripts
5. Then it runs the custom configuration scripts specified in .env (in function prepare_image_extras)
6. Finally, it creates an encrypted disk and writes the build to it

LOGGING

The script logs to the cryptmypi directory, making a log of all actions to the file specified in the .env file.
