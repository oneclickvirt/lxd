#!/bin/bash
# by https://github.com/spiritLHLS/lxc

lxc start "$1"
lxc exec "$1" -- apt update -y
lxc exec "$1" -- sudo dpkg --configure -a
lxc exec "$1" -- sudo apt-get update
lxc exec "$1" -- sudo apt-get install dos2unix curl -y
lxc exec "$1" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
lxc exec "$1" -- chmod 777 ssh.sh
lxc exec "$1" -- dos2unix ssh.sh
lxc exec "$1" -- sudo ./ssh.sh "$2"
echo "$2"
rm -rf "$0"
echo "$2"spiritlhlisyyds
