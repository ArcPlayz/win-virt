#!/usr/bin/xonsh

part_root = '' # NTFS partition to deploy Windows on (ex. /dev/nvme0nXpY, /dev/sdXY)
part_efi = '' # FAT32 EFI partition to copy the Windows bootloader to
iso = '' # path to Windows ISO file
disk = '' # the disk on which those partitions are located (ex. /dev/nvme0nX, /dev/sdX) (it is needed because its GUID has to be inserted into BCD)

# !!! This script won't add Windows Boot Manager to UEFI boot menu !!!
# You should add chainloader entry to your bootloader configuration

# On Limine:

# /Windows
#     protocol: efi
#     path: guid({PARTUUID}):/EFI/Microsoft/Boot/bootmgfw.efi

# You can get {PARTUUID} using blkid
# Also this script will print it

# On GRUB you can use os-prober

# Unattend.xml options (OOBE will be skipped and local user will be automatically created)

user = ''
password = ''

if $(whoami) != 'root':
	input('You should probably run this script as root.\nUse CTRL+C to stop it or ENTER to continue.')

if !(command -v hivexregedit).rtn:
	echo hivexregedit not found! Please install hivex.
	exit

umount --all-targets @(part_root)
umount --all-targets @(part_efi)

# copying windows

mount @(iso) /tmp/win_iso -o ro,loop --mkdir

image = '/tmp/win_iso/sources/install.'

image += 'wim' if not !(test -f @(image + 'wim')).rtn else 'esd'

wimlib-imagex info @(image)

try:
	index = input('index (Ctrl + C to cancel)> ')
except KeyboardInterrupt: raise
else:
	mkfs.ntfs -Q @(part_root)

	wimlib-imagex apply @(image) @(index) @(part_root)
finally:
	umount /tmp/win_iso; rmdir /tmp/win_iso

# copying bootloader

mkfs.fat -F32 @(part_efi)

mount @(part_efi) /tmp/win_efi --mkdir

mount @(part_root) /tmp/win_root --mkdir

mkdir -p /tmp/win_efi/EFI/Microsoft
cp -r /tmp/win_root/Windows/Boot/EFI /tmp/win_efi/EFI/Microsoft/Boot
cp -r /tmp/win_root/Windows/Boot/Resources /tmp/win_efi/EFI/Microsoft/Boot
cp -r /tmp/win_root/Windows/Boot/Fonts /tmp/win_efi/EFI/Microsoft/Boot

# preconfiguring windows

unattend = $(cat unattend.xml.template) \
.replace('{USER}', user) \
.replace('{PASS}', password)

with open('/tmp/win_root/Windows/System32/Sysprep/Unattend.xml', 'w') as fd:
	fd.write(unattend)

umount /tmp/win_root; rmdir /tmp/win_root

# generating bcd

def uuid(part):
	return $(blkid -s PARTUUID -o value @(part))

uuid_disk = $(sgdisk -p @(disk)).split('\n')[3].split()[-1]

from uuid import UUID as oUUID

def uuid_to_reg(_uuid):
	return ','.join(f'{b:02x}' for b in oUUID(_uuid).bytes_le)

bcd = $(cat BCD.reg.template) \
.replace('{ROOT}', uuid_to_reg(uuid(part_root))) \
.replace('{EFI}', uuid_to_reg(uuid(part_efi))) \
.replace('{DISK}', uuid_to_reg(uuid_disk))

cp BCD.template /tmp/win_efi/EFI/Microsoft/Boot/BCD
echo @(bcd) | hivexregedit --merge /tmp/win_efi/EFI/Microsoft/Boot/BCD

umount /tmp/win_efi; rmdir /tmp/win_efi

echo ========== Disk GUID ==========
echo @(uuid_disk)
