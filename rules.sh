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
/usr/bin/dpkg-query flags=noconfirm {,install}zmap, {,install}nmap, {,install}masscan, {,install}medusa
EOL'
apparmor_parser -r /etc/apparmor.d/local/usr.bin.lxc-execute

# 屏蔽流量
iptables -F
blocked_ports=(20 21 22 23 25 53 67 68 69 80 110 139 143 161 389 443 1433 1521 2094 3306 3389 5000 5432 5632 5900 6379 7001 8080 8888 9200 10000 27017 22122 54321 65432 )
for port in "${blocked_ports[@]}"; do
    iptables -A OUTPUT -m owner --uid-owner 100000-165536 -d 0.0.0.0/0 -p tcp --dport "$port" -j DROP
    iptables -A OUTPUT -m owner --uid-owner 100000-165536 -d 0.0.0.0/0 -p udp --dport "$port" -j DROP
done

# 屏蔽网站访问
container_ips=$(lxc list -c 4 | awk '{print $2}')
for container_ip in $container_ips
do
  iptables -A OUTPUT -d zmap.io -j DROP -m comment --comment "block zmap"
  iptables -A OUTPUT -d nmap.org -j DROP -m comment --comment "block nmap"
  iptables -A OUTPUT -d masscan.org -j DROP -m comment --comment "block masscan"
  iptables -A OUTPUT -d foofus.net -j DROP -m comment --comment "block medusa"
done
