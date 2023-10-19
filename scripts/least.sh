#!/usr/bin/env bash
# from
# https://github.com/spiritLHLS/lxd
# cd /root
# ./least.sh NAT服务器前缀 数量
# 2023.10.19

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
lxc init images:debian/11 "$1" -c limits.cpu=1 -c limits.memory=128MiB
lxc config device override "$1" root size=200MB
lxc config device set "$1" root limits.read 500MB
lxc config device set "$1" root limits.write 500MB
lxc config device set "$1" root limits.read 5000iops
lxc config device set "$1" root limits.write 5000iops
lxc config device set "$1" root limits.max 300MB
lxc config device override "$1" eth0 limits.egress=300Mbit limits.ingress=300Mbit
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.cpu.allowance 50%
lxc config set "$1" limits.cpu.allowance 25ms/100ms
lxc config set "$1" limits.memory.swap true
lxc config set "$1" limits.memory.swap.priority 1
lxc config set "$1" security.nesting true
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
    curl -L https://raw.githubusercontent.com/spiritLHLS/lxd/main/scripts/ssh_bash.sh -o /usr/local/bin/ssh_bash.sh
    chmod 777 /usr/local/bin/ssh_bash.sh
    dos2unix /usr/local/bin/ssh_bash.sh
fi
cp /usr/local/bin/ssh_bash.sh /root
if [ ! -f /usr/local/bin/config.sh ]; then
    curl -L https://raw.githubusercontent.com/spiritLHLS/lxd/main/scripts/config.sh -o /usr/local/bin/config.sh
    chmod 777 /usr/local/bin/config.sh
    dos2unix /usr/local/bin/config.sh
fi
cp /usr/local/bin/config.sh /root
# 批量创建容器
for ((a = 1; a <= "$2"; a++)); do
    lxc copy "$1" "$1"$a
    name="$1"$a
    sshn=$((20000 + a))
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
    echo "$name $sshn $passwd" >>log
done
rm -rf ssh_bash.sh config.sh ssh_sh.sh
