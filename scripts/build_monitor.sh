#!/bin/bash
# from
# https://github.com/oneclickvirt/lxd
# 2023.06.29

# 检查 screen 是否已安装
if ! command -v screen &>/dev/null; then
    apt-get update
    apt-get install -y screen
fi

curl -L https://github.com/oneclickvirt/lxd/raw/main/scripts/monitor.sh -o monitor.sh && chmod +x monitor.sh

# 启动一个新的 screen 窗口并在其中运行命令
screen -dmS lxc_moniter bash monitor.sh
