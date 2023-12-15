#!/bin/bash

XOCE_URL=https://nc.nl.tab.digital/s/WQmCwmH4e9EdTTA/download

# Welcome message
printf "\n\033[1mWelcome to the XOCE auto-deploy script!\033[0m\n\n"

if ! which xe 2> /dev/null >&2
then
  echo
  echo 'Sorry, the xe command is required for this auto-deploy.'
  echo
  echo 'Please, make sure you are on a XCP-ng/XenServer host.'
  echo
  exit 1
fi

# Basic check: are we on a XS host?
if grep -Fxq "XenServer" /etc/issue
then
  printf "\nSorry, it seems you are not on a XCP-ng/XenServer host.\n\n"
  printf "\n\033[1mThis script is meant to be deployed on XCP-ng or XenServer only.\033[0m\n\n"
  exit 1
fi

# Initial choice on network settings: fixed IP or DHCP? (default)

printf "Network settings:\n"
read -p "IP address? [dhcp] " ip
ip=${ip:-dhcp}
if [ "$ip" != 'dhcp' ]
then
  read -p "Netmask? [255.255.255.0] " netmask
  netmask=${netmask:-255.255.255.0}
  read -p "Gateway? " gateway
  read -p "dns? [8.8.8.8] " dns
  dns=${dns:-8.8.8.8}
else
  printf "\nYour XOCE installation will be started using DHCP\n\n"
fi

# Downloading and importing the VM

printf "Importing XOCE VM…\n"
uuid=$(xe vm-import url="$XOCE_URL" 2> /dev/null)

# If it fails (it means XS < 7.0)
# We'll use the curl
import=$?
if [ $import -ne 0 ]
then
  uuid=$(curl "$XOCE_URL" | xe vm-import filename=/dev/stdin 2>&1)
fi

# If it fails again (for any reason), we stop the script
import=$?
if [ $import -ne 0 ]
then
  printf "\n\nAuto deploy failed. Please contact us on https://github.com/Jarli01/xenorchestra_installer/issues for assistance.\nError:\n\n %s\n\n" "$uuid"
  exit 0
fi

# If static IP selected, fill the xenstore

if [ "$ip" != 'dhcp' ]
then
  xe vm-param-set uuid=$uuid xenstore-data:vm-data/ip=$ip xenstore-data:vm-data/netmask=$netmask xenstore-data:vm-data/gateway=$gateway xenstore-data:vm-data/dns=$dns
fi

# Starting the VM

printf "Booting XOCE VM…\n"
xe vm-start uuid=$uuid
sleep 2

# Waiting for the VM IP from Xen tools for 60 secs

printf "Waiting for XOCE to be ready…\n"
url=$(xe vm-param-get uuid=$uuid param-name=networks param-key=0/ip 2> /dev/null)
wait=0
limit=60
while [ -z "$url" -a "$wait" -lt "$limit" ]
do
  let wait=wait+1
  sleep 1
  url=$(xe vm-param-get uuid=$uuid param-name=networks param-key=0/ip 2> /dev/null)
done


# End of the process. Display the XOCE URL if possible

# If we use a fixed IP but on a DHCP enabled network
# We don't want to get the first IP displayed by the tools
# But the fixed one

if [ "$ip" != 'dhcp' ]
then
  printf "\n\033[1mYour XOCE is ready at https://%s/\033[0m\n" "$ip"
  # clean the xenstore data
  xe vm-param-remove param-name=xenstore-data param-key=vm-data/dns param-key=vm-data/ip param-key=vm-data/netmask param-key=vm-data/gateway uuid=$uuid

# If we can't fetch the IP from tools

elif [ -z "$url" ]
then
  printf "\n\033[1mYour XOCE booted but we couldn't fetch its IP address\033[0m\n"
else
  printf "\n\033[1mYour XOCE is ready at https://%s/\033[0m\n" "$url"
fi
printf "\nDefault UI credentials: admin@admin.net/admin\nDefault console credentials: xoce/xoce\n"
printf "\nVM UUID: %s\n\n" "$uuid"
