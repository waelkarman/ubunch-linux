#!/usr/bin/env bash
###################################################################################
## Base Configuration
###################################################################################
DISTRO="ubuntu"
RELEASE="noble"
ARCH="amd64"
MAINTAINER="Wael Karman <wael.karman@gmail.com>"
PROJECT_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###################################################################################
## Build Options
###################################################################################
ORIGINAL_IMAGE="ubuntu-24.04.4-live-server-amd64.iso"
ISO_LABEL="UBUNCH-LINUX"
ISO_OUT="ubunch_linux_os"
RUN_IN_QEMU=true

# List of bundle names to install into the image (space-separated or as array)
IMAGE_INSTALL=(
    bash-lib
)

PACKAGES=(
    vim nano curl wget tree tmux htop locate
    inotify-tools
    clevis clevis-tpm2 clevis-luks clevis-initramfs clevis-systemd
    tpm2-tools libsensors-dev lm-sensors
    systemd-boot systemd-boot-efi systemd
)