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

parser = ArgumentParser('deploy')

parser.add_argument(
	'partition_root', type = str, help = 'NTFS partition to deploy Windows on (e.g. /dev/nvme0nXpY, /dev/sdXY)'
)
parser.add_argument(
	'partition_efi', type = str, help = 'FAT32 EFI partition to copy the Windows bootloader to'
)
parser.add_argument(
	'iso', type = str, help = 'path to Windows ISO file'
)
parser.add_argument(
	'username', type = str, help = 'name of the local user that will be created via Unattend.xml'
)
parser.add_argument(
	'password', type = str, help = 'password of the user'
)

args = parser.parse_args()

partition_root, partition_efi, iso, username, password = args.partition_root, args.partition_efi, args.iso, args.username, args.password

if $(whoami) != 'root':
	input('You should probably run this script as root. Use CTRL+C to stop it or ENTER to continue.')

from shutil import which

if not which('hivexregedit'):
	echo "hivexregedit not found! Please install hivex."
	exit(1)

if not which('wimlib-imagex'):
	echo "wimlib-imagex not found! Please install wimlib."
	exit(1)

from json import loads

blockdevices = loads(
	$(lsblk -b -J -o PTTYPE,PATH,PARTUUID,PTUUID)
)['blockdevices']

from collections import namedtuple

part = namedtuple('part', ('uuid', 'uuid_disk'))

parts = {}
for _part in blockdevices:
	if _part['pttype'] == 'gpt':
		parts[_part['path']] = part(
			_part['partuuid'], _part['ptuuid']
		)
if parts[partition_root].uuid_disk != parts[partition_efi].uuid_disk:
	echo "Windows root and EFI partitions are not on the same disk!"
	exit(1)

with unstrict():
	umount -q --all-targets @(partition_root)
	umount -q --all-targets @(partition_efi)

# copying windows

mount @(iso) /tmp/win_iso -o ro,loop --mkdir

image = '/tmp/win_iso/sources/install.'

from pathlib import Path

if Path(image + 'wim').exists():
	image += 'wim'
else:
	image += 'esd'

try:
	wimlib-imagex info @(image)

	index = input('index (Ctrl + C to cancel)> ')
except (KeyboardInterrupt, CalledProcessError): raise
else:
	mkfs.ntfs -Q @(partition_root)

	wimlib-imagex apply @(image) @(index) @(partition_root)
finally:
	umount /tmp/win_iso; rmdir /tmp/win_iso

# copying bootloader

mkfs.fat -F32 @(partition_efi)

mount @(partition_efi) /tmp/win_efi --mkdir

mount @(partition_root) /tmp/win_root --mkdir

mkdir -p /tmp/win_efi/EFI/Microsoft
cp -r /tmp/win_root/Windows/Boot/EFI /tmp/win_efi/EFI/Microsoft/Boot
cp -r /tmp/win_root/Windows/Boot/Resources /tmp/win_efi/EFI/Microsoft/Boot
cp -r /tmp/win_root/Windows/Boot/Fonts /tmp/win_efi/EFI/Microsoft/Boot

# preconfiguring windows

unattend = $(cat unattend.xml.template) \
.replace('{{ username }}', username) \
.replace('{{ password }}', password)

mkdir -p /tmp/win_root/Windows/System32/Sysprep
echo @(unattend) > /tmp/win_root/Windows/System32/Sysprep/Unattend.xml

umount /tmp/win_root; rmdir /tmp/win_root

# generating bcd

from uuid import UUID

def uuid_to_reg(uuid):
	return ','.join(f'{b:02x}' for b in UUID(uuid).bytes_le)

bcd = $(cat BCD.reg.template) \
.replace('{{ partition_root }}', uuid_to_reg(parts[partition_root].uuid)) \
.replace('{{ partition_efi }}', uuid_to_reg(parts[partition_efi].uuid)) \
.replace('{{ disk }}', uuid_to_reg(parts[partition_root].uuid_disk))

cp empty.dat /tmp/win_efi/EFI/Microsoft/Boot/BCD
echo @(bcd) | hivexregedit --merge /tmp/win_efi/EFI/Microsoft/Boot/BCD

umount /tmp/win_efi; rmdir /tmp/win_efi

echo @(parts[partition_root].uuid_disk)

