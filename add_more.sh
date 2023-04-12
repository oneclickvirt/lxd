#!/bin/bash
# from
# https://github.com/spiritLHLS/lxc
# 2023.04.06

# cd /root

red() { echo -e "\033[31m\033[01m$@\033[0m"; }
green() { echo -e "\033[32m\033[01m$@\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading(){ read -rp "$(green "$1")" "$2"; }

pre_check(){
    home_dir=$(eval echo "~$(whoami)")
    if [ "$home_dir" != "/root" ]; then
        red "当前路径不是/root，脚本将退出。"
        exit 1
    fi
    if ! command -v dos2unix > /dev/null 2>&1; then
        apt-get install dos2unix -y
    fi
    if [ ! -f ssh.sh ]; then
        curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
        chmod 777 ssh.sh
        dos2unix ssh.sh
    fi
    if [ ! -f config.sh ]; then
        curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/config.sh -o config.sh
        chmod 777 config.sh
        dos2unix config.sh
    fi
    if [ ! -f buildone.sh ]; then
        curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/buildone.sh -o buildone.sh
        chmod 777 buildone.sh
        dos2unix buildone.sh
    fi
}

check_log(){
    log_file="log"
    if [ -f "$log_file" ]; then
        green "Log文件存在，正在读取内容..."
        while read line; do
            # echo "$line"
            last_line="$line"
        done < "$log_file"
    else
        red "log文件不存在。"
        exit 1
    fi
    last_line_array=($last_line)
    container_name="${last_line_array[0]}"
    ssh_port="${last_line_array[1]}"
    password="${last_line_array[2]}"
    public_port_start="${last_line_array[3]}"
    public_port_end="${last_line_array[4]}"
    if [ -z "$public_port_start" ] || [ -z "$public_port_end" ]; then
      blue "仅支持普通版本的配置批量重复生成，纯探针版本或其他的无法使用"
      exit 1
    fi
    container_prefix="${container_name%%[0-9]*}"
    container_num="${container_name##*[!0-9]}"
    yellow "目前最后一个小鸡的信息："
    blue "容器前缀: $container_prefix"
    blue "容器数量: $container_num"
    blue "SSH端口: $ssh_port"
#     blue "密码: $password"
    blue "外网端口起: $public_port_start"
    blue "外网端口止: $public_port_end"
}

build_new_containers(){
    while true; do
        reading "还需要再生成几个小鸡？(输入新增几个小鸡)：" new_nums
        if [[ "$new_nums" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            yellow "输入无效，请输入一个正整数。"
        fi
    done
    for ((i=1; i<=$new_nums; i++)); do
        container_num=$(($container_num + 1))
        container_name="${container_prefix}${container_num}"
        ssh_port=$(($ssh_port + 1))
        public_port_start=$(($public_port_end + 1))
        public_port_end=$(($public_port_start + 25))
        ./buildone.sh $container_name 256 1 $ssh_port $public_port_start $public_port_end 300 300
        cat "$container_name" >> log
        rm -rf $container_name
    done
}

pre_check
check_log
build_new_containers
green "生成新的小鸡完毕"
check_log
