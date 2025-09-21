This script allows you to deploy Windows from Linux.  
You need [hivex](https://github.com/libguestfs/hivex) and [wimlib (wimlib-imagex)](https://archlinux.org/packages/extra/x86_64/wimlib) to run it.  
"empty.dat" is an empty registry hive file, it was taken from [here](https://github.com/libguestfs/hivex/blob/master/images/minimal)

This script won't add Windows Boot Manager to UEFI boot menu  
You should add chainloader entry to your bootloader configuration

On Limine:

```
/Windows
	protocol: efi
	path: guid({{ PARTUUID }}):/EFI/Microsoft/Boot/bootmgfw.efi
```

You can get {{ PARTUUID }} using blkid  
Also this script will print it

On GRUB you can use os-prober

