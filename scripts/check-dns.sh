#!/bin/bash
#from https://github.com/spiritLHLS/lxc
# 2023.06.29


DNS_SERVER="2001:4860:4860::8844"
RESOLV_CONF="/etc/resolv.conf"

grep -q "^nameserver ${DNS_SERVER}$" ${RESOLV_CONF}

if [ $? -eq 0 ]; then
    echo "DNS server ${DNS_SERVER} already exists in ${RESOLV_CONF}."
else
    chattr -i /etc/resolv.conf
    echo "Adding DNS server ${DNS_SERVER} to ${RESOLV_CONF}..."
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 2606:4700:4700::1111\nnameserver 2001:4860:4860::8888\nnameserver 2001:4860:4860::8844" >> ${RESOLV_CONF}
    chattr +i /etc/resolv.conf
fi
