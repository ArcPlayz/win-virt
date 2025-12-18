#!/usr/bin/env xonsh

from subprocess import CalledProcessError

$RAISE_SUBPROC_ERROR = True

from contextlib import contextmanager

@contextmanager
def unstrict():
	original = $RAISE_SUBPROC_ERROR
	$RAISE_SUBPROC_ERROR = False
	try:
		yield
	finally:
		$RAISE_SUBPROC_ERROR = original

from argparse import ArgumentParser

parser = ArgumentParser('map')

parser.add_argument(
	'partition_root', type = str, help = 'windows NTFS partition (e.g. /dev/nvme0nXpY, /dev/sdXY)'
)
parser.add_argument(
	'partition_efi', type = str, help = 'windows FAT32 EFI partition'
)
parser.add_argument(
	'partition_data', type = str, help = 'partition suitable for sharing files between Linux and Windows'
)

args = parser.parse_args()

partition_root, partition_efi, partition_data = args.partition_root, args.partition_efi, args.partition_data

if $(whoami) != 'root':
	input('You should probably run this script as root. Use CTRL+C to stop it or ENTER to continue.')

from shutil import which

if not which('sgdisk'):
	echo "sgdisk not found! Please install gptfdisk"
	exit(1)

from pathlib import Path

if Path('/tmp/loop_gpt').exists():
	echo "/tmp/loop_gpt exists; it seems that the device is already mapped!"
	exit(1)

from json import loads

blockdevices = loads(
	$(lsblk -b -J -o PTTYPE,PATH,PARTUUID,PTUUID,SIZE)
)['blockdevices']

from collections import namedtuple

part = namedtuple('part', ('uuid', 'size', 'uuid_disk'))

parts = {}
for _part in blockdevices:
	if _part['pttype'] == 'gpt':
		parts[_part['path']] = part(
			_part['partuuid'], _part['size'] // 512, _part['ptuuid']
		)
if parts[partition_root].uuid_disk != parts[partition_efi].uuid_disk:
	echo "Windows root and EFI partitions are not on the same disk!"
	exit(1)

with unstrict():
	umount -q --all-targets @(partition_root)
	umount -q --all-targets @(partition_efi)
	umount -q --all-targets @(partition_data)

if not Path('./gpt').exists():
	dd if=/dev/zero of=gpt bs=512 count=77

ln -s $(losetup -f --show gpt) /tmp/loop_gpt

mapping = f'''\
0 34 linear /tmp/loop_gpt 0
34 {parts[partition_root].size} linear {partition_root} 0
{34 + parts[partition_root].size} {parts[partition_efi].size} linear {partition_efi} 0
{34 + parts[partition_root].size + parts[partition_efi].size} {parts[partition_data].size} linear {partition_data} 0
{34 + parts[partition_root].size + parts[partition_efi].size + parts[partition_data].size} 33 linear /tmp/loop_gpt 34\
'''

echo @(mapping) | dmsetup create windows

sgdisk -o -a 1 \
-U @(parts[partition_root].uuid_disk) \
-n 0::+@(parts[partition_root].size) -t 0:0700 -u 0:@(parts[partition_root].uuid) \
-n 0::+@(parts[partition_efi].size) -t 0:ef00 -u 0:@(parts[partition_efi].uuid) \
-n 0::+@(parts[partition_data].size) -t 0:0700 -u 0:@(parts[partition_data].uuid) \
/dev/mapper/windows

