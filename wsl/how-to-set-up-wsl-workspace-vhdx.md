# How to set up a shared Workspace drive for WSL

This guide follows the pattern used by dev containers in which a single workspace can be mapped into multiple dev containers. In this case we want to have a single VHDX file that serves as a shared workspace that is mounted to all WSL distributions.

## Create a new VHDX file for the shared workspace

Create a new VHDX file. You can do this in PowerShell on Windows with this command.

```PowerShell
# Run this as Administrator
$vhdPath = "$Env:USERPROFILE\wsl\workspace.vhdx"
New-VHD -Path $vhdPath -SizeBytes 200GB -Dynamic
```

## Format the VHDX files as EXT4

In PowerShell on Windows, mount the disk into your default WSL instance.

```PowerShell
wsl.exe --mount --vhd $vhdPath --bare
```

Log into your default WSL instance. Find the disk using the `lsblk` utility. The output will look something like this:

```BASH
$ lsblk
NAME
    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda   8:0    0 388.4M  1 disk
sdb   8:16   0    12G  0 disk [SWAP]
sdc   8:32   0     1T  0 disk /mnt/wslg/distro
                              /
sdd   8:48   0   200G  0 disk
```

Find the `NAME` in the row that corresponds with the disk you mounted. In the example above, the `NAME` is `sdd`.

Format the disk using the command below.

```BASH
# sudo mkfs.ext4 /dev/<NAME>, replacing <NAME> with the NAME output from the lsblk command.

# For example:
$ sudo mkfs.ext4 /dev/sdd
mke2fs 1.47.0 (5-Feb-2023)
Discarding device blocks: done
Creating filesystem with 52428800 4k blocks and 13107200 inodes
Filesystem UUID: ac914a8c-76b0-458a-8237-7b01bf27788c
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
        4096000, 7962624, 11239424, 20480000, 23887872

Allocating group tables: done
Writing inode tables: done
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done
```

Go back to Powershell on Windows, and unmount the VHDX file using this command.

```PowerShell
wsl.exe --unmount $vhdPath
```

## Configure WSL to automatically mount the disk upon startup

This repo contains a script that will mount the workspace drive to all WSL distros upon distro startup. (WSL mount configurations affect all distros.) The must be configured to run from any WSL distro where you want the workspace drive mounted.

The configuration to run the startup script is in the `/etc/wsl.conf` file. If the file does not exist, create it. Otherwise, add the configuration below to the file:

```INI
[boot]
command="<PATH TO YOUR STARTUP SCRIPT, e.g. /mnt/c/repos/dotfiles/wsl/wsl_startup.sh>"
```

Shut down WSL so that the startup script will run the next time you start up a distribution.

```PowerShell
wsl.exe --shutdown
```

Log into the WSL distribution and verify that your workspace has been mounted.

## Change ownership of the workspace mount to the default WSL user

> Note: You only have to do this once for a VHDX workspace file.

```BASH
sudo chown 1000:1000 /mnt/wsl/workspacedemo
```
