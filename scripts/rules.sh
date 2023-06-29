#!/bin/bash
# from https://github.com/spiritLHLS/lxc
# 2023.06.29

# 容器内屏蔽安装包
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

# 容器屏蔽安装包
divert_install_script() {
    local package_name=$1
    local divert_script="/usr/local/sbin/${package_name}-install"
    local install_script="/var/lib/dpkg/info/${package_name}.postinst"
    ln -sf "${divert_script}" "${install_script}"
    sh -c "echo '#!/bin/bash' > ${divert_script}"
    sh -c "echo 'exit 1' >> ${divert_script}"
    chmod +x "${divert_script}"
}

echo "Package: zmap nmap masscan medusa apache2-utils hping3
Pin: release *
Pin-Priority: -1" | sudo tee -a /etc/apt/preferences
apt-get update
divert_install_script "zmap"
divert_install_script "nmap"
divert_install_script "masscan"
divert_install_script "medusa"
divert_install_script "hping3"
divert_install_script "apache2-utils"

# 屏蔽流量
iptables -F
blocked_ports=( 3389 8888 54321 65432 )
for port in "${blocked_ports[@]}"; do
    iptables --ipv4 -I FORWARD -o eth0 -p tcp --dport ${port} -j DROP
    iptables --ipv4 -I FORWARD -o eth0 -p udp --dport ${port} -j DROP
done

# 屏蔽网站访问
container_ips=$(lxc list -c 4 | awk '{print $2}')
for container_ip in $container_ips
do
    iptables -A OUTPUT -d zmap.io -j DROP -m comment --comment "block zmap"
    iptables -A OUTPUT -d nmap.org -j DROP -m comment --comment "block nmap"
    iptables -A OUTPUT -d foofus.net -j DROP -m comment --comment "block medusa"
#     ip6tables -A OUTPUT -d zmap.io -j DROP -m comment --comment "block zmap v6"
done
