# EasyCryptMyPi

## PURPOSE: Creates encrypted raspberry pis running kali linux based on re4son's kali images for RPI
## USAGE: ./cryptmypi.sh .
## EXAMPLE:

./easycryptmypi.sh
    
Please note this script is only tested on:
- Kali Pi host
- Kali Pi 4 64 bit image (Re4son kernel)

## Capabilities
1. FULL DISK ENCRYPTION
- Encrypted using a cipher of your choice
- Remote unlock via Dropbear
- Accessible via ethernet or wifi if configured 
- Bypass firewalls using IODINE (NOT TESTED)
- Nuke password configurable
2. OPERATIONAL
- Check the hash of your boot directory on startup
- Reduce battery usage with cpu-governor
- Configure network adapters and DNS
- Configure root password
- Configure Client OpenVPN (NOT TESTED)
- Docker (NOT TESTED)
- Configure SSH with authorized_keys or password login; (NOT TESTED)

## Installation
Clone this git repo/Download from github
