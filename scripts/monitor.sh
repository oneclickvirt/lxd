#!/bin/bash
# from
# https://github.com/spiritLHLS/lxc
# 2023.06.29

if ! command -v jq > /dev/null 2>&1; then
    apt-get install jq -y
fi
echo $$ > /tmp/lxc_monitor.pid
echo "The monitoring PID is the contents of the /tmp/lxc_monitor.pid file, which can be viewed by executing cat /tmp/lxc_monitor.pid"
echo "监控PID为 /tmp/lxc_monitor.pid 文件中的内容，可执行 cat /tmp/lxc_monitor.pid 查看"
# 指定关键词列表
KEYWORDS=("xmrig" "masscan" "zmap" "nmap" "medusa" "webBenchmark" "hping3")
while true; do
    # 获取所有运行中的容器名字
    CONTAINERS=$(lxc list --format=json | jq -r '.[] | select(.status == "Running") | .name')
    for container in $CONTAINERS; do
        # 获取容器中的所有进程名字
        PROCESS_NAMES=$(lxc exec $container -- ps -eo comm=)
        for keyword in "${KEYWORDS[@]}"; do
            # 检查进程名字是否包含关键词
            if echo "$PROCESS_NAMES" | grep -q "\<$keyword\>"; then
                # 停止容器并记录日志
                lxc stop $container
                echo "container $container stopped due to process with keyword '$keyword'." >> /var/log/container_monitor.log
                break
            fi
        done
    done
    # 等待 1 分钟
    sleep 60
done
rm -rf /tmp/lxc_monitor.pid
