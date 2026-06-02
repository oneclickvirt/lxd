#!/usr/bin/env bash
# from
# https://github.com/oneclickvirt/lxd
# 2026.02.28

# 输入
# ./modify.sh 服务器名称 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N)
# 如果 外网起端口 外网止端口 都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意不能为空，不进行映射需要设置为0

validate_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

validate_non_negative_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

validate_port() {
    validate_non_negative_int "$1" && [ "$1" -le 65535 ]
}

validate_positive_port() {
    validate_positive_int "$1" && [ "$1" -le 65535 ]
}

validate_inputs() {
    if ! validate_positive_port "$sshn" || ! validate_port "$nat1" || ! validate_port "$nat2"; then
        echo "Error: ports must be integers in range 0-65535, and SSH port must be greater than 0."
        echo "错误：端口必须是 0-65535 的整数，SSH 端口必须大于 0。"
        exit 1
    fi
    if { [ "$nat1" = "0" ] && [ "$nat2" != "0" ]; } || { [ "$nat1" != "0" ] && [ "$nat2" = "0" ]; }; then
        echo "Error: NAT port range must either be both 0 or both non-zero."
        echo "错误：NAT 端口起止必须同时为 0，或同时为非 0。"
        exit 1
    fi
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ] && [ "$nat1" -gt "$nat2" ]; then
        echo "Error: NAT start port cannot be greater than NAT end port."
        echo "错误：NAT 起始端口不能大于结束端口。"
        exit 1
    fi
    if ! validate_positive_int "$in" || ! validate_positive_int "$out"; then
        echo "Error: speed values must be positive integers."
        echo "错误：网速参数必须是正整数。"
        exit 1
    fi
}

replace_proxy_device() {
    local device_name="$1"
    shift
    if lxc config device show "$name" 2>/dev/null | grep -q "^${device_name}:"; then
        lxc config device remove "$name" "$device_name" 2>/dev/null || true
    fi
    lxc config device add "$name" "$device_name" proxy "$@"
}

remove_device_if_exists() {
    local device_name="$1"
    if lxc config device show "$name" 2>/dev/null | grep -q "^${device_name}:"; then
        lxc config device remove "$name" "$device_name" 2>/dev/null || true
    fi
}

# 创建容器
cd /root >/dev/null 2>&1
name="${1:-test}"
sshn="${2:-20001}"
nat1="${3:-20002}"
nat2="${4:-20025}"
in="${5:-300}"
out="${6:-300}"
enable_ipv6="${7:-N}"
enable_ipv6=$(echo "$enable_ipv6" | tr '[:lower:]' '[:upper:]')
validate_inputs
if ! lxc info "$name" >/dev/null 2>&1; then
    echo "Error: container '$name' does not exist."
    echo "错误：容器 '$name' 不存在。"
    exit 1
fi
# 支持docker虚拟化
lxc config set "$name" security.nesting true
ori=$(date | md5sum)
passwd=${ori:2:9}
lxc start "$name" 2>/dev/null || true
sleep 1
# 从容器内探测系统类型
system=$(lxc exec "$name" -- sh -c "grep -i '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' | tr '[:upper:]' '[:lower:]'" 2>/dev/null || echo "debian")
/usr/local/bin/check-dns.sh
if echo "$system" | grep -qiE "centos" || echo "$system" | grep -qiE "almalinux" || echo "$system" | grep -qiE "fedora" || echo "$system" | grep -qiE "rocky"; then
    lxc exec "$name" -- sudo yum update -y
    lxc exec "$name" -- sudo yum install -y curl
    lxc exec "$name" -- sudo yum install -y dos2unix
elif echo "$system" | grep -qiE "alpine"; then
    lxc exec "$name" -- apk update
    lxc exec "$name" -- apk add --no-cache curl
elif echo "$system" | grep -qiE "openwrt"; then
    lxc exec "$name" -- opkg update
else
    lxc exec "$name" -- sudo apt-get update -y
    lxc exec "$name" -- sudo apt-get install curl -y --fix-missing
    lxc exec "$name" -- sudo apt-get install dos2unix -y --fix-missing
fi
if echo "$system" | grep -qiE "alpine" || echo "$system" | grep -qiE "openwrt"; then
    if [ ! -f /usr/local/bin/ssh_sh.sh ]; then
        curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_sh.sh -o /usr/local/bin/ssh_sh.sh
        chmod 777 /usr/local/bin/ssh_sh.sh
        dos2unix /usr/local/bin/ssh_sh.sh
    fi
    cp /usr/local/bin/ssh_sh.sh /root
    lxc file push /root/ssh_sh.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh_sh.sh
    lxc exec "$name" -- ./ssh_sh.sh ${passwd}
else
    if [ ! -f /usr/local/bin/ssh_bash.sh ]; then
        curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh -o /usr/local/bin/ssh_bash.sh
        chmod 777 /usr/local/bin/ssh_bash.sh
        dos2unix /usr/local/bin/ssh_bash.sh
    fi
    cp /usr/local/bin/ssh_bash.sh /root
    lxc file push /root/ssh_bash.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh_bash.sh
    lxc exec "$name" -- dos2unix ssh_bash.sh
    lxc exec "$name" -- sudo ./ssh_bash.sh $passwd
    if [ ! -f /usr/local/bin/config.sh ]; then
        curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh -o /usr/local/bin/config.sh
        chmod 777 /usr/local/bin/config.sh
        dos2unix /usr/local/bin/config.sh
    fi
    cp /usr/local/bin/config.sh /root
    lxc file push /root/config.sh "$name"/root/
    lxc exec "$name" -- chmod +x config.sh
    lxc exec "$name" -- dos2unix config.sh
    lxc exec "$name" -- bash config.sh
    lxc exec "$name" -- history -c
fi
replace_proxy_device ssh-port listen=tcp:0.0.0.0:$sshn connect=tcp:0.0.0.0:22 nat=true
# 是否要创建V6地址
if [ -n "$enable_ipv6" ]; then
    if [ "$enable_ipv6" == "Y" ]; then
        lxc exec "$name" -- sh -c 'echo "*/1 * * * * curl -m 6 -s ipv6.ip.sb && curl -m 6 -s ipv6.ip.sb" | crontab -'
        sleep 1
        if [ ! -f "./build_ipv6_network.sh" ]; then
            # 如果不存在，则从指定 URL 下载并添加可执行权限
            curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/build_ipv6_network.sh -o build_ipv6_network.sh && chmod +x build_ipv6_network.sh
        fi
        ./build_ipv6_network.sh "$name"
    fi
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
    replace_proxy_device nattcp-ports listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:0.0.0.0:$nat1-$nat2 nat=true
    replace_proxy_device natudp-ports listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:0.0.0.0:$nat1-$nat2 nat=true
else
    remove_device_if_exists nattcp-ports
    remove_device_if_exists natudp-ports
fi
# 网速
lxc stop "$name"
if ((in == out)); then
    speed_limit="$in"
else
    speed_limit=$(($in > $out ? $in : $out))
fi
# 上传 下载 最大
if ! lxc config device override "$name" eth0 limits.egress="$out"Mbit limits.ingress="$in"Mbit limits.max="$speed_limit"Mbit 2>/dev/null; then
    lxc config device set "$name" eth0 limits.egress "$out"Mbit
    lxc config device set "$name" eth0 limits.ingress "$in"Mbit
    lxc config device set "$name" eth0 limits.max "$speed_limit"Mbit
fi
lxc start "$name"
rm -rf ssh_bash.sh config.sh ssh_sh.sh
if echo "$system" | grep -qiE "alpine"; then
    sleep 3
    lxc stop "$name"
    lxc start "$name"
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
    echo "$name $sshn $passwd $nat1 $nat2" >"$name"
    echo "$name $sshn $passwd $nat1 $nat2"
    exit 0
fi
if [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
    echo "$name $sshn $passwd" >"$name"
    echo "$name $sshn $passwd"
fi
