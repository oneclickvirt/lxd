#!/bin/bash
lxc init images:debian/bullseye "$1" -c limits.cpu=1 -c limits.memory=1024MiB
lxc config device override "$1" root size=5GB
lxc config device set "$1" root limits.read 100MB
lxc config device set "$1" root limits.write 100MB
lxc config device set "$1" root limits.read 150iops
lxc config device set "$1" root limits.write 100iops
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.network.priority 0
lxc config set "$1" limits.memory.swap false
# 批量创建容器
for ((a=1;a<"$3";a++)); do
  lxc copy "$1" "$1"$a
  name="$1"$a
  sshn=$(( 22222 + a ))
  nat1=$(( 30000 + (a-1)*25 + 1))
  nat2=$(( 30000 + a*25 ))
  ori=$(date | md5sum)
  passwd=${ori: 2: 9}
  lxc start "$1"$a
  sleep 1
  lxc exec "$1"$a -- apt update -y
  lxc exec "$1"$a -- sudo dpkg --configure -a
  lxc exec "$1"$a -- sudo apt-get update
  lxc exec "$1"$a -- sudo apt-get install dos2unix curl -y
  lxc exec "$1"$a -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
  lxc exec "$1"$a -- chmod 777 ssh.sh
  lxc exec "$1"$a -- dos2unix ssh.sh
  lxc exec "$1"$a -- sudo ./ssh.sh $passwd
  lxc config device add "$1"$a ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
  lxc config device add "$1"$a nat-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
  echo "$name $sshn $passwd $nat1 $nat2" >> log
done
