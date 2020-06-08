#! /bin/bash

USER=tracerte

NETMGRCFG=$(cat <<CFG
network:
  version: 2
  renderer: NetworkManager
CFG
)
GDMCFG=$(cat <<CFG
# GDM configuration storage
#
# See /usr/share/gdm/gdm.schemas for a list of available options.

[daemon]
# Uncomment the line below to force the login screen to use Xorg
#WaylandEnable=false
InitialSetupEnable=false

# Enabling automatic login
#  AutomaticLoginEnable = true
#  AutomaticLogin = user1

# Enabling timed login
#  TimedLoginEnable = true
#  TimedLogin = user1
#  TimedLoginDelay = 10

[security]

[xdmcp]

[chooser]

[debug]
# Uncomment the line below to turn on debugging
# More verbose logs
# Additionally lets the X server dump core if it crashes
#Enable=true
CFG
)

if [ $# -ne 1 ]
then
  echo "Usage: $0 <system_type>"
  echo "Where <system_type> is 'terminal' or 'desktop'"
  echo "Example: $0 terminal"
  exit 1
fi

echo "Setting Up User"
UUID=$(dd if=/dev/urandom of=/dev/stdout bs=1 count=100 2>/dev/null |
    tr -dc 'a-z0-9' | cut -c-6)
ROOT_DS=$(zfs list -o name | awk '/ROOT\/ubuntu_/{print $1;exit}')
zfs create -o com.ubuntu.zsys:bootfs-datasets=$ROOT_DS \
    -o canmount=on -o mountpoint=/home/"${USER}" \
    rpool/USERDATA/"${USER}"_"${UUID}"
adduser "${USER}"

cp -a /etc/skel/. /home/"${USER}"
chown -R "${USER}":"${USER}" /home/"${USER}"
usermod -a -G adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo "${USER}"

echo "Disabling Log Compression to save CPU Cycles"

for file in /etc/logrotate.d/* ; do
    if grep -Eq "(^|[^#y])compress" "$file" ; then
        sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "$file"
    fi
done

echo "Upgrading the minimal system"

apt dist-upgrade --yes

SYSTEMTYPE=$(echo "$1" | tr '[:upper:]' '[:lower:]')

if [ "${SYSTEMTYPE}" == "desktop" ]
then
  echo "Installing Desktop environment"
  apt install --yes ubuntu-desktop

  rm -f /etc/gdm3/custom.conf
  echo "$GDMCFG" > /etc/gdm3/custom.conf

  rm -f /etc/netplan/01-netcfg.yaml
  echo "$NETMGRCFG" > /etc/netplan/01-network-manager-all.yaml
elif [ "${SYSTEMTYPE}" == "terminal" ]
then
  echo "Installing Terminal environment"
  apt install --yes ubuntu-standard
else
  echo "Error: The system type specified is not valid. Are you sure about ${SYSTEMTYPE}?"
fi

echo "Please reboot"