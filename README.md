# Ubuntu ZFS LUKS Provisioning Scripts

A three step set of shell scripts for provisioning both servers and desktops with ZFS, both RAID and single disk, and encrypted with LUKS.

## Usage of `1_install_base.sh`

Open the file and populate the variables:

Swap:

`SWAPSIZE=8           # IN GB`

Hostname:

`HOSTNAME=test-host`

Network:

To find your working network:

```sh
$ ip addr show

```

`NETWORK=enp0s3`

RAID Level:

Choices include:
 - ""
 - mirror
 - raidz 
 - raidz2
 - raidz3
RAIDLEVEL=""

Disks:

Find your block devices using:

```sh
$ lsblk
```

`DISKS=(sda)`

Disk ID lookup:

Choices Include:
 - ata
 - scsi
 - wwn

`DISKIDTYPE="ata"`

### Execution

Run as root

```sh
$ bash 1_install_base.sh
```

## Usage of `2_post_install.sh`

Open the file and populate the following variables

User:

The desired system user.

`USER=tracerte`

### Execution

Run as root and choose between `terminal` or `desktop` for installation

```sh
$ bash 2_post_install.sh "terminal"
$ bash 2_post_install.sh "desktop"
```

## Usage of `3_cleanup.sh`

Disks:

Find your block devices using:

```sh
$ lsblk
```

`DISKS=(sda)`

Disk ID lookup:

Choices Include:
 - ata
 - scsi
 - wwn

`DISKIDTYPE="ata"`

LUKS Header Backup

`LUKSHEADERDIR=/root/luks_headers`

### Execution

```sh
$ bash 3_cleanup.sh
```

## Adding a Disk to Single Disk Setup Post Installation

This will automatically be set the mirro.

### Partitioning and Formatting

Identify the new disk's ID under `/dev/disks/by-id`. Set it as a variable.

```sh
DISK=/dev/disk/by-id/<my-disk>

sgdisk     -n1:1M:+512M   -c1:"EFI System Partition" -t1:EF00 "${DISK}"
sgdisk     -n2:0:+<swap>G   -c2:"Swap" -t2:FD00 "${DISK}"
sgdisk     -n3:0:+2G  -c3:"Boot Pool" -t3:BE00 "${DISK}"
sgdisk     -n4:0:+<original_root>G  -c4:"Root Pool" -t4:8309 "${DISK}"

mkdosfs -F 32 -s 1 -n EFI "${DISK}-part1"

cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha256 "${DISK}-part4"
cryptsetup luksOpen "${DISK}-part4 luks2"
```

### Attach New Disk to Zpools

```sh
# zpool attach nameofpool /dev/disk/by-id/currentdisk /dev/disk/by-id/newdisk
zpool attach bpool /dev/disk/by-id/currentdisk /dev/disk/by-id/newdisk
zpool attach rpool /dev/mapper/currentluks /dev/mapper/newluks
```

### Edit `/etc/crypttab` and `/etc/fstab`

```/etc/crypttab
...
luks2 UUID=<new-uuid-rpool> none luks,discard,initramfs
...
```

```/etc/fstab
...
UUID=<new-uuid-efi> /boot/efi2 vfat umask=0022,fmask=0022,dmask=0022 0 1
...
```

### Add New Swap Partition to RAID MDADM

```sh
$ mdadm --add /dev/md0 /dev/sdb
```

### Install Grub

```sh
mkdir /boot/efi2
mount /boot/efi2

update-initramfs -c -k all
update-grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi2 \
    --bootloader-id=ubuntu --recheck --no-floppy
```

### Backup New LUK Device's Header

```sh
sudo cryptsetup luksHeaderBackup "${DISK}-part4"  \
    --header-backup-file /directory/of/your/choice/luks2-header.dat   
```
