# basic_cryptmypi
basic_cryptmypi - A really simple kali pi build script.
With thanks to unixabg for the original script.

THIS IS A BETA, DON'T DOWNLOAD UNLESS YOU ARE PREPARED TO TROUBLESHOOT

PURPOSE

Creates a configurable kali sd card or disk image for the raspberry pi with strong encryption as default.

See file env.sh-example-template for a full list of options

Testing is 'ad hoc' and only for the RPI4. Other kernels might work if set in env.sh

USAGE

Leave aside about 30GB of space for this

Usage: sudo ./cryptmypi.sh ARG1

BEFORE Running the script. make sure you first create your env.sh based on one of the examples or the template.
Then comment in/out the functions in optional_setup to what you want.
If you forget to add a variable in, the script may exit and tell you or choose a reasonable default.
The script also checks for ordering of optional setup.

ARG1 can be:
-b or build - standard build
-nx or build_no_extract - build without preparing the filesystem
-m or mount_only - only mount an image or disk
-u or unmount - unmount
-i or initramfs - mount and run mkinitramfs
-h or help - prints this help message
-o or optional_only - mounts and runs whats in optional setup

Follow the prompts

ISSUES

- Mounts need manually unmounting, sometimes
- Some optional setup options aren't fully tested

LOGGING

The script logs to the cryptmypi directory file build.log
