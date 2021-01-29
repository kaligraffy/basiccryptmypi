# basic_cryptmypi
basic_cryptmypi - A really simple kali pi build script.
With thanks to unixabg for the original script.

THIS IS A WORK IN PROGRESS, DON'T DOWNLOAD UNLESS YOU ARE PREPARED TO TROUBLESHOOT

USAGE

Leave aside about 30GB of space for this

Usage: sudo ./cryptmypi.sh ARG1

BEFORE Running the script. make sure you first create your env.sh based on one of the examples or the template.
Then comment in/out the functions in optional_setup to what you want.
If you forget to add a variable in, the script may exit and tell you or choose a reasonable default.
The script also checks for ordering of optional setup.

ARG1 can be:
-b or build - standard build
-nx or build_no_extract - build without preparing the filesystem, useful if your script fails on an optional setup and you don't want to copy again
-m or mount_only - only mount an image or disk
-u or unmount - unmount
-h or help - prints this help message

Follow the prompts

PURPOSE

Creates a configurable kali sd card or usb for the raspberry pi with strong encryption as default. The following 
options should be descriptive enough, but look in options.sh for what each one does:

See file env.sh-example-template for a full list of options

Testing is 'ad hoc' and only for the RPI4. Other kernels might work if set in env.sh

ISSUES

Mounts need manually unmounting, sometimes

HOW DOES IT WORK

LOGGING

The script logs to the cryptmypi directory
