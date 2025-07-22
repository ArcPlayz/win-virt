#!/bin/xonsh

part_data = ''
mountpoint_data = ''

if $(whoami) != 'root':
	input('You should probably run this script as root.\nUse CTRL+C to stop it or ENTER to continue.')

dmsetup remove windows

losetup -d $(readlink /tmp/loop_gpt)
rm /tmp/loop_gpt

# assuming we use exfat, we have to specify uid to grant permissions

mount @(part_data) @(mountpoint_data) -o uid=1000,gid=1000

