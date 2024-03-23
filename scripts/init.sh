#!/usr/bin/env bash
# from
# https://github.com/oneclickvirt/lxd
# cd /root
# ./init.sh NAT服务器前缀 数量
# 2024.03.23

cd /root >/dev/null 2>&1
if [ ! -d "/usr/local/bin" ]; then
  mkdir -p "$directory"
fi

check_china() {
    echo "IP area being detected ......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国，使用中国镜像完成相关组件安装"
            CN=true
        else
            if [[ $? -ne 0 ]]; then
                if [[ $(curl -m 6 -s cip.cc) =~ "中国" ]]; then
                    echo "根据cip.cc提供的信息，当前IP可能在中国，使用中国镜像完成相关组件安装"
                    CN=true
                fi
            fi
        fi
    fi
}

check_china
rm -rf log
lxc init opsmaru:debian/12 "$1" -c limits.cpu=1 -c limits.memory=256MiB
# 硬盘大小
if [ -f /usr/local/bin/lxd_storage_type ]; then
    storage_type=$(cat /usr/local/bin/lxd_storage_type)
else
    storage_type="btrfs"
fi
lxc storage create "$1" "$storage_type" size=1GB >/dev/null 2>&1
lxc config device override "$1" root size=1GB
lxc config device set "$1" root limits.max 1GB
# IO
lxc config device set "$1" root limits.read 500MB
lxc config device set "$1" root limits.write 500MB
lxc config device set "$1" root limits.read 5000iops
lxc config device set "$1" root limits.write 5000iops
# 网速
lxc config device override "$1" eth0 limits.egress=300Mbit
lxc config device override "$1" eth0 limits.ingress=300Mbit
lxc config device override "$1" eth0 limits.max=300Mbit
# cpu
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.cpu.allowance 50%
lxc config set "$1" limits.cpu.allowance 25ms/100ms
# 内存
lxc config set "$1" limits.memory.swap true
lxc config set "$1" limits.memory.swap.priority 1
# 支持docker虚拟化
lxc config set "$1" security.nesting true
# 安全性防范设置 - 只有Ubuntu支持
# if [ "$(uname -a | grep -i ubuntu)" ]; then
#   # Set the security settings
#   lxc config set "$1" security.syscalls.intercept.mknod true
#   lxc config set "$1" security.syscalls.intercept.setxattr true
# fi
# 屏蔽端口
blocked_ports=(3389 8888 54321 65432)
for port in "${blocked_ports[@]}"; do
  iptables --ipv4 -I FORWARD -o eth0 -p tcp --dport ${port} -j DROP
  iptables --ipv4 -I FORWARD -o eth0 -p udp --dport ${port} -j DROP
done
if [ ! -f /usr/local/bin/ssh_bash.sh ]; then
  curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh -o /usr/local/bin/ssh_bash.sh
  chmod 777 /usr/local/bin/ssh_bash.sh
  dos2unix /usr/local/bin/ssh_bash.sh
fi
cp /usr/local/bin/ssh_bash.sh /root
if [ ! -f /usr/local/bin/config.sh ]; then
  curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh -o /usr/local/bin/config.sh
  chmod 777 /usr/local/bin/config.sh
  dos2unix /usr/local/bin/config.sh
fi
cp /usr/local/bin/config.sh /root
# 批量创建容器
for ((a = 1; a <= "$2"; a++)); do
  lxc copy "$1" "$1"$a
  name="$1"$a
  # 容器SSH端口 20000起  外网nat端口 30000起 每个25个端口
  sshn=$((20000 + a))
  nat1=$((30000 + (a - 1) * 25 + 1))
  nat2=$((30000 + a * 25))
  ori=$(date | md5sum)
  passwd=${ori:2:9}
  lxc start "$1"$a
  sleep 1
  if [[ "${CN}" == true ]]; then
      lxc exec "$name" -- yum install -y curl
      lxc exec "$name" -- apt-get install curl -y --fix-missing
      lxc exec "$1"$a -- curl -lk https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh -o ChangeMirrors.sh
      lxc exec "$1"$a -- chmod 777 ChangeMirrors.sh
      lxc exec "$1"$a -- ./ChangeMirrors.sh --source mirrors.tuna.tsinghua.edu.cn --web-protocol http --intranet false --close-firewall true --backup true --updata-software false --clean-cache false --ignore-backup-tips
      lxc exec "$1"$a -- rm -rf ChangeMirrors.sh
  fi
  lxc exec "$1"$a -- sudo apt-get update -y
  lxc exec "$1"$a -- sudo apt-get install curl -y --fix-missing
  lxc exec "$1"$a -- sudo apt-get install -y --fix-missing dos2unix
  lxc file push /root/ssh_bash.sh "$1"$a/root/
  lxc exec "$1"$a -- chmod 777 ssh_bash.sh
  lxc exec "$1"$a -- dos2unix ssh_bash.sh
  lxc exec "$1"$a -- sudo ./ssh_bash.sh $passwd
  lxc file push /root/config.sh "$1"$a/root/
  lxc exec "$1"$a -- chmod +x config.sh
  lxc exec "$1"$a -- dos2unix config.sh
  lxc exec "$1"$a -- bash config.sh
  lxc config device add "$1"$a ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
  lxc config device add "$1"$a nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
  lxc config device add "$1"$a natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
  echo "$name $sshn $passwd $nat1 $nat2" >>log
done
rm -rf ssh_bash.sh config.sh ssh_sh.sh
