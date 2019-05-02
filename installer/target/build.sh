# (c) 2014-2015 Sam Nazarko
# email@samnazarko.co.uk

#!/bin/bash

. ../../scripts/common.sh

echo -e "Building target side installer"
BUILDROOT_VERSION="2014.05"

echo -e "Installing dependencies"
update_sources
verify_action
packages="build-essential
rsync
texinfo
libncurses5-dev
whois
bc
dosfstools
mtools
parted
cpio
python"

if [ "$1" == "vero2" ] || [ "$1" == "vero3" ]
then
   packages="abootimg u-boot-tools $packages"
fi

for package in $packages
do
	install_package $package
	verify_action
done

pull_source "http://buildroot.uclibc.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz" "."
verify_action
pushd buildroot-${BUILDROOT_VERSION}
install_patch "../patches" "all"
install_patch "../patches" "$1"
if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ]
then
	install_patch "../patches" "rbp"
	sed s/rpi-firmware/rpi-firmware-osmc/ -i package/Config.in # Use our own firmware package
	echo "dwc_otg.fiq_fix_enable=1 sdhci-bcm2708.sync_after_dma=0 dwc_otg.lpm_enable=0 console=tty1 root=/dev/ram0 quiet init=/init loglevel=2 osmcdev=${1}" > package/rpi-firmware-osmc/cmdline.txt
fi
make osmc_defconfig
make
if [ $? != 0 ]; then echo "Build failed" && exit 1; fi
popd
pushd buildroot-${BUILDROOT_VERSION}/output/images
if [ -f ../../../filesystem.tar.xz ]
then
    echo -e "Using local filesystem"
else
    echo -e "Downloading latest filesystem"
    date=$(date +%Y%m%d)
    count=150
    while [ $count -gt 0 ]; do wget --spider -q ${DOWNLOAD_URL}/filesystems/osmc-${1}-filesystem-${date}.tar.xz
           if [ "$?" -eq 0 ]; then
	        wget ${DOWNLOAD_URL}/filesystems/osmc-${1}-filesystem-${date}.tar.xz -O $(pwd)/../../../filesystem.tar.xz
                break
           fi
           date=$(date +%Y%m%d --date "yesterday $date")
           let count=count-1
    done
fi
if [ ! -f ../../../filesystem.tar.xz ]; then echo -e "No filesystem available for target" && exit 1; fi

## start image creation
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# parts are taken from https://github.com/LibreELEC/LibreELEC.tv/blob/9.0.1/scripts/mkimage

echo -e "Building disk image"
if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ] || [ "$1" == "vero2" ] || [ "$1" == "vero3" ]; then size=256; fi
date=$(date +%Y%m%d)
if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ] || [ "$1" == "vero1" ] || [ "$1" == "vero2" ] || [ "$1" == "vero3" ]
then

  # set variables
  DISK_TMP=$(mktemp -d)
  SAVE_ERROR="${DISK_TMP}/save_error"
  # just set this as default
  SYSTEM_PART_START=8192
  SYSTEM_SIZE=${size}
  # for now only msdos, but gpt should work too
  DISK_LABEL=msdos
  # used in LE for a 2nd partition
  STORAGE_SIZE=32 # STORAGE_SIZE must be >= 32 !
  DISTRO_BOOTLABEL=OSMC
  DISK_START_PADDING=$(( (${SYSTEM_PART_START} + 2048 - 1) / 2048 ))
  DISK_GPT_PADDING=1
  DISK_SIZE=$(( ${DISK_START_PADDING} + ${SYSTEM_SIZE} + ${STORAGE_SIZE} + ${DISK_GPT_PADDING} ))
  DISK_BASENAME="OSMC_TGT_${1}_${date}"
  DISK="${DISK_BASENAME}.img"

  # functions
  cleanup() {
    echo -e "image: cleanup...\n"
    rm -rf "${DISK_TMP}"
  }

  show_error() {
    echo "image: An error has occurred..."
    echo
    if [ -s "${SAVE_ERROR}" ]; then
      cat "${SAVE_ERROR}"
    else
      echo "Folder ${DISK_TMP} might be out of free space..."
    fi
    echo
    cleanup
    exit 1
  }

  trap cleanup SIGINT

  # generate volume id for fat partition
  UUID_1=$(date '+%d%m')
  UUID_2=$(date '+%M%S')
  FAT_SERIAL_NUMBER="${UUID_1}${UUID_2}"
  UUID_SYSTEM="${UUID_1}-${UUID_2}"

  # create an image
  echo -e "\nimage: creating file $(basename ${DISK})..."
  dd if=/dev/zero of="${DISK}" bs=1M count="${DISK_SIZE}" conv=fsync >"${SAVE_ERROR}" 2>&1 || show_error

  # write a disklabel
  echo "image: creating ${DISK_LABEL} partition table..."
  parted -s "${DISK}" mklabel ${DISK_LABEL}
  sync

  # create part1
  echo "image: creating part1..."
  SYSTEM_PART_END=$(( ${SYSTEM_PART_START} + (${SYSTEM_SIZE} * 1024 * 1024 / 512) - 1 ))
  if [ "${DISK_LABEL}" = "gpt" ]; then
    parted -s "${DISK}" -a min unit s mkpart system fat32 ${SYSTEM_PART_START} ${SYSTEM_PART_END}
    parted -s "${DISK}" set 1 legacy_boot on
  else
    parted -s "${DISK}" -a min unit s mkpart primary fat32 ${SYSTEM_PART_START} ${SYSTEM_PART_END}
    parted -s "${DISK}" set 1 boot on
  fi
  sync

  # create filesystem on part1
  echo "image: creating filesystem on part1..."
  OFFSET=$(( ${SYSTEM_PART_START} * 512 ))
  HEADS=4
  TRACKS=32
  SECTORS=$(( ${SYSTEM_SIZE} * 1024 * 1024 / 512 / ${HEADS} / ${TRACKS} ))

  mformat="mformat -i ${DISK}@@${OFFSET} -h ${HEADS} -t ${TRACKS} -s ${SECTORS}"
  mcopy="mcopy -i ${DISK}@@${OFFSET}"
  mmd="mmd -i ${DISK}@@${OFFSET}"

  $mformat -v "${DISTRO_BOOTLABEL}" -N "${FAT_SERIAL_NUMBER}" ::
  sync

fi

if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ]
then
	###
	### this is a guess and not tested
	###
	echo -e "Installing Pi files"
	mcopy zImage ::/kernel.img
	for i in `ls -1 INSTALLER/*`; do
	    $mcopy $i ::
	done
	for i in `ls -1 *.dtb`; do
	    $mcopy $i ::
	done
	$mcopy overlays ::
fi
if [ "$1" == "vero2" ]
then
	###
	### this is a guess and not tested
	###
	echo -e "Installing Vero 2 files"
	abootimg --create ${DISK_TMP}/kernel.img -k uImage -r rootfs.cpio.gz -s ../build/linux-master/arch/arm/boot/dts/amlogic/meson8b_vero2.dtb
	$mcopy "${DISK_TMP}/kernel.img" ::
fi
if [ "$1" == "vero3" ]
then
	echo -e "Installing Vero 3 files"
	../.././output/build/linux-master/scripts/multidtb/multidtb -o multi.dtb --dtc-path $(pwd)/../../output/build/linux-master/scripts/dtc/ $(pwd)/../../output/build/linux-master/arch/arm64/boot/dts/amlogic --verbose --page-size 2048
	abootimg --create ${DISK_TMP}/kernel.img -k Image.gz -r rootfs.cpio.gz -s multi.dtb -c "kerneladdr=0x1080000" -c "pagesize=0x800" -c "ramdiskaddr=0x1000000" -c "secondaddr=0xf00000" -c "tagsaddr=0x100"
	$mcopy "${DISK_TMP}/kernel.img" ::
	$mcopy multi.dtb ::/dtb.img
fi
echo -e "Installing filesystem"
$mcopy "$(pwd)/../../../filesystem.tar.xz" :: && rm $(pwd)/../../../filesystem.tar.xz
sync

# extract part1 from image to run fsck
echo "image: extracting part1 from image..."
SYSTEM_PART_COUNT=$(( ${SYSTEM_PART_END} - ${SYSTEM_PART_START} + 1 ))
sync
dd if="${DISK}" of="${DISK_TMP}/part1.fat" bs=512 skip="${SYSTEM_PART_START}" count="${SYSTEM_PART_COUNT}" conv=fsync >"${SAVE_ERROR}" 2>&1 || show_error
echo "image: checking filesystem on part1..."
fsck -n "${DISK_TMP}/part1.fat" >"${SAVE_ERROR}" 2>&1 || show_error

## end image creation change

echo -e "Compressing image"
gzip ${DISK}
md5sum ${DISK}.gz > ${DISK}.gz.md5
popd
mv buildroot-${BUILDROOT_VERSION}/output/images/${DISK}* .
echo -e "Build completed"

cleanup
