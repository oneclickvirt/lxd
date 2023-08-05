#!/bin/sh
# by https://github.com/spiritLHLS/lxc
# 2023.08.05

if [ "$(cat /etc/os-release | grep -E '^ID=' | cut -d '=' -f 2)" != "alpine" ]
then
  echo "This script only supports Alpine Linux."
  exit 1
fi
if [ "$(id -u)" -ne 0 ]
then
  echo "This script must be executed with root privileges."
  exit 1
fi
apk add --no-cache openssh-server sshpass openssh-keygen
if [ -f "/etc/motd" ]; then
    echo 'Related repo https://github.com/spiritLHLS/lxc' >> /etc/motd
    echo '--by https://t.me/spiritlhl' >> /etc/motd
fi
cd /etc/ssh
ssh-keygen -A
sed -i '/^#PermitRootLogin\|PermitRootLogin/c PermitRootLogin yes' /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config
sed -i '/^#ListenAddress\|ListenAddress/c ListenAddress 0.0.0.0' /etc/ssh/sshd_config
sed -i '/^#AddressFamily\|AddressFamily/c AddressFamily any' /etc/ssh/sshd_config
sed -i "s/^#\?\(Port\).*/\1 22/" /etc/ssh/sshd_config
sed -i -E 's/^#?(Port).*/\1 22/' /etc/ssh/sshd_config
sed -E -i 's/preserve_hostname:[[:space:]]*false/preserve_hostname: true/g' /etc/cloud/cloud.cfg
sed -E -i 's/disable_root:[[:space:]]*true/disable_root: false/g' /etc/cloud/cloud.cfg
sed -E -i 's/ssh_pwauth:[[:space:]]*false/ssh_pwauth:   true/g' /etc/cloud/cloud.cfg
/usr/sbin/sshd
rc-update add sshd default
echo root:"$1" | chpasswd root
rm -f "$0"
