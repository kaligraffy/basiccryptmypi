# EasyCryptMyPi

## PURPOSE: 
Creates an encrypted kali raspberry pi with:
- disk encryption with strong defaults, 
- btrfs file system, 
- a nuke password,
- ssh setup and enabled on port 2222,
- dropbear on 2222 on initramfs,
- your chosen extra packages

## USAGE: 

1. Inspect env.sh and make changes as necessary.
  - Most variables can be changed (be sure to test some and let me know)
  - Change any passwords called CHANGEME, the nuke password default is a '.' :)
  - Load optional or experimental modules in the prepare_image_extra function (just uncomment them)
2. Run sudo ./cryptmypi.sh

The script doesn't have any help or usage functions implemented to cut down on the amount of code.
If you have a problem just ask on the git.

I've tried to keep sensible defaults in the .env 

Please note this script is only tested on:
- Kali Pi host
- Kali Pi 4 64 bit image (Re4son kernel)

## Capabilities
In theory, this should work for any raspberry pi image you want to customize, have a go and tell me if it actually works...

## Installation
Clone this git repo/Download from github

## Thanks to the original author for most of the code - unix
