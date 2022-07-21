#!/bin/bash
lxc init images:"$6" "$1" -c limits.cpu=1 -c limits.memory=1024MiB
lxc config device override "$1" root size=10GB
lxc config device override "$1" root limits.read 200MB
lxc config device override "$1" root.limits.write 200MB
lxc config device override "$1" root limits.read 150Iops
lxc config device override "$1" root limits.write 150Iops
lxc config device override "$1" root limits.cpu.priority 0
lxc config device override "$1" root limits.disk.priority 0
lxc config device override "$1" root limits.network.priority 0
lxc start "$1"
lxc exec "$1" -- sudo apt-get install dos2unix curl wget -y
lxc exec "$1" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
lxc exec "$1" -- dos2unix ssh.sh
lxc exec "$1" -- chmod +x ssh.sh
lxc exec "$1" -- sudo ./ssh.sh "$2"
lxc config device add "$1" ssh-port proxy listen=tcp:0.0.0.0:"$3" connect=tcp:127.0.0.1:22
lxc config device add "$1" nat-ports proxy listen=tcp:0.0.0.0:"$4"-"$5" connect=tcp:127.0.0.1:5000-5025
echo "$2"
rm -rf "$0"
