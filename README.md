# basiccryptmypi

## PURPOSE: Creates encrypted raspberry pis running kali linux
    
## USAGE: ./cryptmypi.sh [OPTIONS] configuration_dir

## EXAMPLE:

./cryptmypi.sh --device /dev/sda /examples/kali-complete 
- Executes script using examples/kali-complete/cryptmypi.conf as config directory
- using /dev/sda as destination block device
    
Please note this script is only tested on, previous versions aren't supported by me:
- Kali Pi host
- Kali Pi 4 64 bit image (Re4son kernel)

## How it works

A configuration profile defines 2 stages:

- Stage 1. The OS image is extracted and built.
- Stage 2. The build is written to an SD card.

## Capabilities

1. FULL DISK ENCRYPTION
- Encrypted using a cipher of your choice (defaults are reasonably secure as of today)
- Remote unlock via Dropbear
- Accessible via ethernet or wifi if configured 
- Bypass firewalls using IODINE (NOT TESTED)
- Nuke password configurable.

2. OPERATIONAL
- Reduce battery usage with ondemand-cpu-governor
- Configure network adapters and DNS
- Configure root password
- Configure Client OpenVPN (NOT TESTED)
- Configure SSH with authorized_keys or password login; (NOT TESTED)

## Installation

Clone this git repo/Download from github
