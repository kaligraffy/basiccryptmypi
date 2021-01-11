# basiccryptmypi
basiccryptmypi - A really simple kali pi build script.
With thanks to unixabg for the original script.

THIS IS A WORK IN PROGRESS, DON'T DOWNLOAD UNLESS YOU ARE PREPARED TO TROUBLESHOOT

USAGE

- Leave aside about 20GB of disk space 
- git clone https://github.com/kaligraffy/basiccryptmypi.git
- cd cryptmypi
-  Rename an example .env file or fill in the template.env file
- ./cryptmypi
- Follow the prompts

PURPOSE

Creates a configurable kali sd card or usb for the raspberry pi with strong encryption as default. The following 
options should be descriptive enough, but look in options.sh for what each one does:

See file env.sh-example-template for a full list of options

Testing is 'ad hoc' and only for the RPI4. Oher kernels might work if set in env.sh

ISSUES

Mounts don't get cleaned up properly, if this is the case run: losetup -D; umount /dev/loop/*;

HOW DOES IT WORK

1. The script downloads the image using the URL specified in the .env file (if it's already there it skips downloading it)
2. Then it extracts the image (if it's already there it asks if you want to re-extract)
3. Then it copies the contents to a directory called 'root' in the build directory
4. Then it runs the normal configuration 
5. Then it runs the custom configuration specified in .env (in function extra_setup)
6. Finally, it creates an encrypted disk and writes the build to it

LOGGING

The script logs to the cryptmypi directory
