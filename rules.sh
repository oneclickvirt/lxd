#!/bin/bash
# from https://github.com/spiritLHLS/lxc

# 屏蔽安装包
if ! dpkg -s apparmor &> /dev/null; then
  apt-get install apparmor
fi
containers=$(lxc list -c n | awk '{print $2}')
for container_name in $containers
do
  echo "lxc profile set $container_name restrictions" \
    "apparmor='/usr/bin/zmap Cx,'\
    '/usr/bin/nmap Cx,'\
    '/usr/bin/masscan Cx,'\
    '/usr/bin/medusa Cx,'"
done
sudo bash -c 'cat > /etc/apparmor.d/local/usr.bin.lxc-execute << EOL
# AppArmor profile for lxc-execute

# Deny installation of specified tools
/usr/bin/dpkg-query flags=noconfirm {,install}zmap, {,install}nmap, {,install}masscan, {,install}medusa
EOL'
apparmor_parser -r /etc/apparmor.d/local/usr.bin.lxc-execute

# 屏蔽流量
iptables -F
blocked_ports=(22 21 54321 80 8080 443 3389)
for port in "${blocked_ports[@]}"; do
    iptables -A OUTPUT -m owner --uid-owner 100000-165536 -d 0.0.0.0/0 -p tcp --dport "$port" -j DROP
    iptables -A OUTPUT -m owner --uid-owner 100000-165536 -d 0.0.0.0/0 -p udp --dport "$port" -j DROP
done

# 屏蔽仓库访问
