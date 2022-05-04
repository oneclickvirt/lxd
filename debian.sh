#!/bin/bash
lxc init images:debian/bullseye "$1" -c limits.cpu=1 -c limits.memory=1024MiB
lxc config device override "$1" root size=8GB
lxc start "$1"
lxc exec "$1" -- sudo apt-get install dos2unix curl -y
lxc exec "$1" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
lxc exec "$1" -- dos2unix ssh.sh
lxc exec "$1" -- chmod +x ssh.sh
lxc exec "$1" -- sudo ./ssh.sh "$2"
lxc config device add "$1" ssh-port proxy listen=tcp:0.0.0.0:"$3" connect=tcp:127.0.0.1:22
lxc config device add "$1" nat-ports proxy listen=tcp:0.0.0.0:"$4"-"$5" connect=tcp:127.0.0.1:5000-5025
lxc exec "$1" -- sudo ./ssh.sh "$2"
echo "$2"
