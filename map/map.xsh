#!/usr/bin/xonsh

part_root = '' # Windows partition (ex. /dev/nvme0nXpY, /dev/sdXY)
part_efi = '' # Windows EFI partition
disk = '' # the disk on which root and EFI partitions are located (its GUID has to be added to virtual GPT scheme)
part_data = '' # ExFAT partition suitable for sharing files between Linux and Windows

# !!! When "gpt" file (virtual GPT scheme) is already created and you change the size of any of
# !!! provided partitions you have to remove it so it will be created again
# !!! Otherwise the data will get corrupted

if $(whoami) != 'root':
	input('You should probably run this script as root.\nUse CTRL+C to stop it or ENTER to continue.')

if !(command -v sgdisk).rtn:
	echo sgdisk not found! Please install gptfdisk
	exit

umount --all-targets @(part_root)
umount --all-targets @(part_efi)
umount --all-targets @(part_data)

def size(part):
	return int(
		$(blockdev --getsz @(part))
	)

if !(test -f gpt).rtn:
	dd if=/dev/zero of=gpt bs=512 count=77

	generate = True
else:
	generate = False

if !(test -f /tmp/loop_gpt).rtn:
	ln -s $(losetup -f --show gpt) /tmp/loop_gpt

mapping = f'''\
0 34 linear /tmp/loop_gpt 0
34 {size(part_root)} linear {part_root} 0
{34 + size(part_root)} {size(part_efi)} linear {part_efi} 0
{34 + size(part_root) + size(part_efi)} {size(part_data)} linear {part_data} 0
{34 + size(part_root) + size(part_efi) + size(part_data)} 33 linear /tmp/loop_gpt 34\
'''

echo @(mapping) | dmsetup create windows

def uuid(part):
	return $(blkid -s PARTUUID -o value @(part))

if generate:
	uuid_disk = $(sgdisk -p @(disk)).split('\n')[3].split()[-1]

	sgdisk -o -a 1 \
	-U @(uuid_disk) \
	-n 0::+@(size(part_root)) -t 0:0700 -u 0:@(uuid(part_root)) \
	-n 0::+@(size(part_efi)) -t 0:ef00 -u 0:@(uuid(part_efi)) \
	-n 0::+@(size(part_data)) -t 0:0700 -u 0:@(uuid(part_data)) \
	/dev/mapper/windows

