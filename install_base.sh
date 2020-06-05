#! /bin/bash

# Log onto LIVECD Environment with GRUB BOOT parameter added: inst.gpt
# This will force gpt installation.

# Become root
# $ sudo su
# Add password to ubuntu user
# $ passwd ubuntu
# Install vim and ssh
# $ apt update
# $ apt install --yes openssh-server vim
# Start SSH
# $ systemctl start sshd
# Find public IP
# $ ifconfig
# Transfer a copy of this script using scp to the remote
# $ scp -P 22 ubuntu_zfs_luks.sh ubuntu@<ip>:~/ubuntu_zfs_luks.sh
# SSH from local to remote
# $ ssh ubuntu@<ip> -p 22
# Become Root and run script
SWAPSIZE=8           # IN GB
HOSTNAME=test-host
# To find your working network:
# $ ip addr show
NETWORK=enp0s3
# You can find your device using:
# $ lsblk
# To check your UUIDs
# $ blkid

# To start fresh on disk if error
# $mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}
# zpool export -a
# $ cryptsetup luksRemoveKey /dev/sdax
# $ cryptsetup -v luksClose luks1
# $ wipefs -a /dev/sda[1-4]
# $ sgdisk --zap-all sda

DISK=sda

NETCFG=$(cat <<CFG
network:
  version: 2
  ethernets:
    $NETWORK:
      dhcp4: true
CFG
)

APTSRCS=$(cat <<SRCS
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
SRCS
)

GRUBCFG=$(cat <<CFG
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.
# For full documentation of the options in this file, see:
#   info -f grub -n 'Simple configuration'

GRUB_DEFAULT=0
# GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=$(lsb_release -i -s 2> /dev/null || echo Debian)
GRUB_CMDLINE_LINUX_DEFAULT="init_on_alloc=0"
GRUB_CMDLINE_LINUX=""

# Uncomment to enable BadRAM filtering, modify to suit your needs
# This works with Linux (no patch required) and with any kernel that obtains
# the memory map information from GRUB (GNU Mach, kernel of FreeBSD ...)
#GRUB_BADRAM="0x01234567,0xfefefefe,0x89abcdef,0xefefefef"

# Uncomment to disable graphical terminal (grub-pc only)
GRUB_TERMINAL=console

# The resolution used on graphical terminal
# note that you can use only modes which your graphic card supports via VBE
# you can see them in real GRUB with the command vbeinfo
#GRUB_GFXMODE=640x480

# Uncomment if you don't want GRUB to pass "root=UUID=xxx" parameter to Linux
#GRUB_DISABLE_LINUX_UUID=true

# Uncomment to disable generation of recovery mode menu entries
#GRUB_DISABLE_RECOVERY="true"

# Uncomment to get a beep at grub start
#GRUB_INIT_TUNE="480 440 1"
CFG
)

# Functions
ee(){
  if [ "$1" -ne 0 ]
  then
    echo "[ERROR] ${2}"
    exit "$1"
  fi
}

echo "Adding Universe Repository"
apt-add-repository universe
apt update

echo "Install ZFS and Disk Partitioning Tools"
apt install --yes debootstrap gdisk zfs-initramfs
systemctl stop zed

DISKID=$(find /dev/disk/by-id -type l -printf "%f:%l\n" | grep -E "${DISK}" | cut -d':' -f 1)
if [ -z "${DISKID}" ]
then
  ee 1 "Could not lookup disk by id... are you sure '${DISK}' is correct?"
fi
DISKDEV="/dev/disk/by-id/${DISKID}"

echo "USING DISK: ${DISKDEV}"
echo "If this is wrong, press Ctrl^C within 15 seconds"
sleep 5
echo "10s"
sleep 5
echo "5s"
sleep 5

echo "Destroying existing partitions"
sgdisk --zap-all "${DISKDEV}"
ee $? "Could not install partition table"
sgdisk     -n1:1M:+512M   -c1:"EFI System Partition" -t1:EF00 "${DISKDEV}"
ee $? "Could not create EFI partition"
sgdisk     -n2:0:+"${SWAPSIZE}"G   -c2:"Swap" -t2:8200 "${DISKDEV}" # Single Disk
ee $? "Could not create SWAP partition"
sgdisk     -n3:0:+2G  -c3:"Boot Pool" -t3:BE00 "${DISKDEV}"
ee $? "Could not create Boot Pool"
sgdisk     -n4:0:0  -c4:"Root Pool" -t4:8309 "${DISKDEV}"
ee $? "Could not create Root Pool"

echo "Ensure Partitions are Correct"
echo "If this is wrong, press Ctrl^C within 10 seconds"
sgdisk -p /dev/sda
sleep 10

EFI="${DISKID}-part1"
EFIDEV=/dev/disk/by-id/$EFI

SWAP="${DISKID}-part2"
SWAPDEV=/dev/disk/by-id/$SWAP

BPOOL="${DISKID}-part3"
BPOOLDEV=/dev/disk/by-id/$BPOOL

RPOOL="${DISKID}-part4"
RPOOLDEV=/dev/disk/by-id/$RPOOL

echo "Creating EFI FAT Partition"
mkdosfs -F 32 -s 1 -n EFI ${EFIDEV}
ee $? "Error create EFI FAT Partition"

EFIUUID=$(blkid -s UUID -o value "$EFIDEV")

echo "Creating BootPool"

zpool create \
    -o ashift=12 -d \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -o feature@zpool_checkpoint=enabled \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O devices=off -O normalization=formD -O relatime=on -O xattr=sa \
    -O mountpoint=/boot -R /mnt \
    bpool "${BPOOLDEV}"
ee $? "Could not create zpool bpool"

echo "Please ensure zpool created..."
echo "If this is wrong, press Ctrl^C within 15 seconds"
zfs list
sleep 15

echo "Setting up LUKS partition, please set a password"
cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha256 "${RPOOLDEV}"
ee $? "Error setting up LUKS"

echo "Please decrypt the LUKS partition"
cryptsetup luksOpen "${RPOOLDEV}" luks1
ee $? "Error decrypting RPOOL"

echo "Creating RPOOL from LUKS"
zpool create \
    -o ashift=12 \
    -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    rpool /dev/mapper/luks1
ee $? "Error create RPOOL"

echo "Please ensure zpool created..."
echo "If this is wrong, press Ctrl^C within 10 seconds"
zfs list
sleep 10

RPOOLUUID=$(blkid -s UUID -o value "$RPOOLDEV")

echo "Please check that the UUID Environment Variables have populated. Continuing in 10 seconds"

echo "EFIUUID = ${EFIUUID}"
echo "RPOOLUUID = ${RPOOLUUID}"
sleep 10

echo "Installing and mounting dataset containers for Root and Boot filesystems"
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT

DISKUUID=$(dd if=/dev/urandom of=/dev/stdout bs=1 count=100 2>/dev/null |
    tr -dc 'a-z0-9' | cut -c-6)

zfs create -o canmount=noauto -o mountpoint=/ \
    -o com.ubuntu.zsys:bootfs=yes \
    -o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/ubuntu_"$DISKUUID"
zfs mount rpool/ROOT/ubuntu_"$DISKUUID"

zfs create -o canmount=noauto -o mountpoint=/boot \
    bpool/BOOT/ubuntu_"$DISKUUID"
zfs mount bpool/BOOT/ubuntu_"$DISKUUID"

echo "Creating and mounting additional dataset containers for data directories"
zfs create -o com.ubuntu.zsys:bootfs=no \
    rpool/ROOT/ubuntu_"$DISKUUID"/srv
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off \
    rpool/ROOT/ubuntu_"$DISKUUID"/usr
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/usr/local
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off \
    rpool/ROOT/ubuntu_"$DISKUUID"/var
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/games
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/lib
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/lib/AccountsService
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/lib/apt
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/lib/dpkg
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/lib/NetworkManager
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/log
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/mail
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/snap
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/spool
zfs create rpool/ROOT/ubuntu_"$DISKUUID"/var/www

zfs create -o canmount=off -o mountpoint=/ \
    rpool/USERDATA
zfs create -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/ubuntu_"$DISKUUID" \
    -o canmount=on -o mountpoint=/root \
    rpool/USERDATA/root_"$DISKUUID"

echo "Creating GRUB directory on bpool"
zfs create bpool/BOOT/ubuntu_"$DISKUUID"/grub

echo "Create tempfs to prevent snapshots of /temp"

zfs create -o com.ubuntu.zsys:bootfs=no \
    rpool/ROOT/ubuntu_"$DISKUUID"/tmp
chmod 1777 /mnt/tmp

echo "Please ensure zpool partitions created and mounted..."
echo "If this is wrong, press Ctrl^C within 15 seconds"
zfs list
sleep 15

echo "Bootstrapping System"

debootstrap focal /mnt

echo "Configuring System"

echo "Setting Up Hostname"
echo $HOSTNAME > /mnt/etc/hostname
echo "127.0.1.1 ${HOSTNAME}" >> /mnt/etc/hosts

echo "Setting Up Network"
rm -f /mnt/etc/netplan/01-netcfg.yaml
echo "$NETCFG" > /mnt/etc/netplan/01-netcfg.yaml
echo "Does this look correct?"
echo "If not Ctrl^C in 10 seconds"
cat /mnt/etc/netplan/01-netcfg.yaml
sleep 10

echo "Setting up Apt Sources"
rm -f /mnt/etc/apt/sources.list
echo "$APTSRCS" > /mnt/etc/apt/sources.list
echo "Does this look correct?"
echo "If not Ctrl^C in 10 seconds"
cat /mnt/etc/apt/sources.list
sleep 10

echo "Setting Up /mnt/etc/crypttab"
echo luks1 UUID="${RPOOLUUID}" none \
    luks,discard,initramfs > /mnt/etc/crypttab
echo swap "${SWAPDEV}" /dev/urandom \
      swap,cipher=aes-xts-plain64:sha256,size=512 >> /mnt/etc/crypttab

echo "Does this look correct?"
echo "If not Ctrl^C in 10 seconds"
cat /mnt/etc/crypttab
sleep 10

echo "Setting Up /mnt/etc/fstab"
echo UUID="${EFIUUID}" \
    /boot/efi vfat umask=0022,fmask=0022,dmask=0022 0 1 >> /mnt/etc/fstab
echo /dev/mapper/swap none swap defaults 0 0 >> /mnt/etc/fstab
echo "Does this look correct?"
echo "If not Ctrl^C in 10 seconds"
cat /mnt/etc/fstab
sleep 10

echo "Binding Virtual Filesystem from LiveCD to new system"
mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys

cat <<"EOF" >> /mnt/chroot_install.sh
#! /bin/bash
apt update
dpkg-reconfigure locales
dpkg-reconfigure tzdata
apt install --yes vim cryptsetup dosfstools

mkdir /boot/efi
mount /boot/efi
apt install --yes \
    grub-efi-amd64 grub-efi-amd64-signed linux-image-generic \
    shim-signed zfs-initramfs zsys
dpkg --purge os-prober
echo "Set Root User Password"
passwd
echo "Create System Groups"
addgroup --system lpadmin
addgroup --system lxd
addgroup --system sambashare
echo "Patch Dependency Loop for LUKS"
sudo apt install --yes curl patch
curl https://launchpadlibrarian.net/478315221/2150-fix-systemd-dependency-loops.patch | \
    sed "s|/etc|/lib|;s|\.in$||" | (cd / ; patch -p1)
echo "Grub Probing ZFS"
echo "Does this look correct? Moving on in 5 seconds"
grub-probe /boot
sleep 5
echo "Refresh initrd files"
update-initramfs -c -k all
echo "Setting Up Grub"
rm -f /etc/default/grub
echo "$GRUBCFG" > /etc/default/grub
update-grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=ubuntu --recheck --no-floppy
mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
zed -F &
pid=$!
echo "Sleeping for 10 seconds to give time to populate zpool cache files"
sleep 10
echo "Cache files should be populated. Please see below for output. Cancel with CTRL^C in 10 seconds. Otherwise Killing zed and continuing install"
cat /etc/zfs/zfs-list.cache/bpool /etc/zfs/zfs-list.cache/rpool
sleep 10
kill -9 $pid
echo "Fixing zfs mount points"
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*
echo "Install ssh server"
apt install --yes openssh-server
echo "Configuring ssh server to allow Root login. PLEASE TURN THIS OFF AFTER INSTALLATION"
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
EOF

chmod +x /mnt/chroot_install.sh
echo "Running /mnt/chroot_install.sh"
chroot /mnt /usr/bin/env GRUBCFG="$GRUBCFG" \
                         bash -c "./chroot_install.sh"
ee $? "Error encountered during execution of chroot_install.sh"

echo "Unmounting Filesystem and Exporting ZFS"
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | \
    xargs -i{} umount -lf {}
zpool export -a

echo "DONE. Please reboot"






