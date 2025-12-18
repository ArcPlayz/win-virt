#!/usr/bin/env xonsh

if $(whoami) != 'root':
	input('You should probably run this script as root. Use CTRL+C to stop it or ENTER to continue.')

dmsetup remove windows

losetup -d $(readlink /tmp/loop_gpt)
rm /tmp/loop_gpt
