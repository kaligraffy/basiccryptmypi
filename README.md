# cryptmypi for rpi4

Assists in the full setup of [encrypted] Raspberry Pis.
Modular configurations hooks

**Note:** Only tested on:
RPI 4B

## How it works

A configuration profile defines 2 stages:

1. A base OS image is extracted.
2. The build is written to an SD card.

Optional configuration hooks can be set in any of the stages:
- Configurations applyed on stage 1 will be avaiable to the stage 2. Each time the script runs it will check if a stage 1 build is already present, and will ask if it should be used or if it should be rebuilt.
- Stage 2 can be executed as many times as wanted without affecting stage's 1 build. Every configuration applyed in stage 2 will be applyed directly to the SD card.

## Capabilities

1. **FULL DISK ENCRYPTION**: Although the project can be used to setup an unencrypted RPi box, it is currently capable to setup a fully encrypted Kali or Pi OS Linux.

- unlockable remotely through dropbear's ssh;
- served through ethernet or wifi;
- exposed to the internet using reverse forwarding: sshhub.de as a jumphost;
- bypass firewalls using IODINE;
- and a nuke password can be set;

2. **OPERATIONAL**: System optional hooks can assis in many commonly configurations.

- setting ondemand cpu governor to reduce battery usage;
- wireless network / adaptors can be pre-configured;
- system DNS server configuration;
- changing the root password;
- openVPN client configuration;
- ssh service, with authorized_keys;

## Scenarios

Example configurations are provided in the the project examples directory.

Each example outlines a possible configurations scenario, from building a standard kali to building an encrypted drop box RPi for remote control.

## Installation

Clone this git repo.

## Usage

Simply:

$ `./cryptmypi.sh configuration_profile_directory`

`configuration_profile_directory` should be an existing configuration directory. Use one of the provided examples or create your own.
