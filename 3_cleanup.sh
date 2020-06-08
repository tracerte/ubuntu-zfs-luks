#! /bin/bash

DISKS=(sda)
# Choices Include:
# - ata
# - scsi
# - wwn
DISKIDTYPE="ata"
LUKSHEADERDIR=/root/luks_headers
GRUBCFG=$(cat <<CFG
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.
# For full documentation of the options in this file, see:
#   info -f grub -n 'Simple configuration'

GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=$(lsb_release -i -s 2> /dev/null || echo Debian)
GRUB_CMDLINE_LINUX_DEFAULT="init_on_alloc=0 quiet splash"
GRUB_CMDLINE_LINUX=""

# Uncomment to enable BadRAM filtering, modify to suit your needs
# This works with Linux (no patch required) and with any kernel that obtains
# the memory map information from GRUB (GNU Mach, kernel of FreeBSD ...)
#GRUB_BADRAM="0x01234567,0xfefefefe,0x89abcdef,0xefefefef"

# Uncomment to disable graphical terminal (grub-pc only)
# GRUB_TERMINAL=console

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

echo "Disabling root user's password"

usermod -p '*' root

echo "Disabling SSH root user login"
sed -i 's/^PermitRootLogin yes/#PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "Installing GRUB custom defaults"
rm -f /etc/default/grub
echo "${GRUBCFG}" > /etc/default/grub
update-grub

echo "Backing Up LUKS headers to specified directory: ${LUKSHEADERDIR}"
mkdir -p "${LUKSHEADERDIR}"

# Get part 4's 
#  grep ".{1,}-part4"

RPOOLIDS=($(for d in "${DISKS[@]}"; do find /dev/disk/by-id -type l -printf "%f:%l\n" | grep -E "${d}4" | cut -d':' -f 1  |  grep -E "$DISKIDTYPE.+"; done))

if [ "${#RPOOLIDS[@]}" -ne "${#DISKS[@]}" ]
then
  ee 1 "Could not lookup disks by id... are you sure they are correct? '${DISKS[*]}'"
fi

RPOOLDEVS=($(for d in "${RPOOLIDS[@]}"; do echo "/dev/disk/by-id/${d}" ; done))
LUKSS=($(for d in "${!RPOOLIDS[@]}"; do i=$((++d)); echo "luks${i}" ; done))


for i in  "${!RPOOLDEVS[@]}"
do
    echo "Saving LUKS header for: ${LUKSS[i]}"
    sudo cryptsetup luksHeaderBackup "${RPOOLDEVS[i]}" \
    --header-backup-file "${LUKSHEADERDIR}"/"${LUKSS[i]}"-header.dat
    ee $? "Error creating header backup for ${LUKSS[i]}"
done

