#!/bin/bash

# Check if we were effectively run as root
[ $EUID = 0 ] || { echo "This script needs to be run as root!"; exit 1; }

# Check for required memory
totalk=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
if [ "$totalk" -lt "2000000" ]; then echo "XOCE Requires at least 2GB Memory!"; exit 1; fi 

distro=$(/usr/bin/lsb_release -is)
if [ "$distro" = "Ubuntu" ]; then /usr/bin/add-apt-repository multiverse; fi

xo_branch="master"
xo_server="https://github.com/vatesfr/xen-orchestra"
n_repo="https://raw.githubusercontent.com/tj/n/master/bin/n"
yarn_repo="deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main"
yarn_gpg="https://dl.yarnpkg.com/debian/pubkey.gpg"
n_location="/usr/local/bin/n"
xo_server_dir="/opt/xen-orchestra"
systemd_service_dir="/lib/systemd/system"
xo_service="xo-server.service"

# Ensures that Yarn dependencies are installed
/usr/bin/apt-get update
/usr/bin/apt-get --yes install git curl apt-transport-https gnupg

#Install yarn
cd /opt

/usr/bin/curl -sSL $yarn_gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "$yarn_repo" | tee /etc/apt/sources.list.d/yarn.list
/usr/bin/apt-get update
/usr/bin/apt-get install --yes yarn

# Install n
/usr/bin/curl -o $n_location $n_repo
/bin/chmod +x $n_location

# Install node via n
n 18

# Symlink node directories
ln -s /usr/bin/node /usr/local/bin/node

# Install XO dependencies
/usr/bin/apt-get install --yes build-essential redis-server libpng-dev git python3-minimal libvhdi-utils nfs-common lvm2 cifs-utils

/usr/bin/git clone -b $xo_branch $xo_server

cd $xo_server_dir
/usr/bin/yarn
/usr/bin/yarn build

cd packages/xo-server
cp sample.config.toml .xo-server.toml

dest=/usr/local/lib/node_modules/
#Create node_modules directory if doesn't exist
mkdir -p $dest

# Plugins to ignore
ignoreplugins=("xo-server-test")

# Symlink all plugins
for source in $(ls -d /opt/xen-orchestra/packages/xo-server-*); do
  plugin=$(basename $source)
  if [[ "${ignoreplugins[@]}" =~ $plugin ]]; then
      echo "Ignoring $plugin plugin"
  else
      ln -s "$source" "$dest"
    fi
done

if [[ -e $systemd_service_dir/$xo_service ]] ; then
  rm $systemd_service_dir/$xo_service
fi

/bin/cat << EOF >> $systemd_service_dir/$xo_service
# Systemd service for XO-Server.

[Unit]
Description= XO Server
After=network-online.target

[Service]
WorkingDirectory=/opt/xen-orchestra/packages/xo-server/
ExecStart=/usr/local/bin/node ./dist/cli.mjs

Restart=always
SyslogIdentifier=xo-server

[Install]
WantedBy=multi-user.target
EOF


/bin/systemctl daemon-reload
/bin/systemctl enable $xo_service
/bin/systemctl start $xo_service

echo ""
echo ""
echo "Installation complete, open a browser to:" && hostname -I && echo "" && echo "Default Login:"admin@admin.net" Password:"admin"" && echo "" && echo "Don't forget to change your password!"

