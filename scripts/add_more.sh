#!/bin/bash
# from
# https://github.com/spiritLHLS/lxc
# 2023.06.29

# cd /root

red() { echo -e "\033[31m\033[01m$@\033[0m"; }
green() { echo -e "\033[32m\033[01m$@\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading(){ read -rp "$(green "$1")" "$2"; }
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
if [[ -z "$utf8_locale" ]]; then
  yellow "No UTF-8 locale found"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  green "Locale set to $utf8_locale"
fi

check_cdn() {
  local o_url=$1
  for cdn_url in "${cdn_urls[@]}"; do
    if curl -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" > /dev/null 2>&1; then
      export cdn_success_url="$cdn_url"
      return
    fi
    sleep 0.5
  done
  export cdn_success_url=""
}

check_cdn_file() {
    check_cdn "https://raw.githubusercontent.com/spiritLHLS/ecs/main/back/test"
    if [ -n "$cdn_success_url" ]; then
        echo "CDN available, using CDN"
    else
        echo "No CDN available, no use CDN"
    fi
}

cdn_urls=("https://cdn.spiritlhl.workers.dev/" "https://cdn3.spiritlhl.net/" "https://cdn1.spiritlhl.net/" "https://ghproxy.com/" "https://cdn2.spiritlhl.net/")
check_cdn_file

pre_check(){
    home_dir=$(eval echo "~$(whoami)")
    if [ "$home_dir" != "/root" ]; then
        red "Current path is not /root, script will exit."
        red "当前路径不是/root，脚本将退出。"
        exit 1
    fi
    if ! command -v dos2unix > /dev/null 2>&1; then
        apt-get install dos2unix -y
    fi
    if [ ! -f ssh.sh ]; then
        curl -sLk "${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/ssh.sh" -o ssh.sh
        chmod 777 ssh.sh
        dos2unix ssh.sh
    fi
    if [ ! -f config.sh ]; then
        curl -sLk "${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/config.sh" -o config.sh
        chmod 777 config.sh
        dos2unix config.sh
    fi
    if [ ! -f buildone.sh ]; then
        curl -sLk "${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/buildone.sh" -o buildone.sh
        chmod 777 buildone.sh
        dos2unix buildone.sh
    fi
}

check_log(){
    log_file="log"
    if [ -f "$log_file" ]; then
        green "Log file exists, content being read..."
        green "Log文件存在，正在读取内容..."
        while read line; do
            # echo "$line"
            last_line="$line"
        done < "$log_file"
        last_line_array=($last_line)
        container_name="${last_line_array[0]}"
        ssh_port="${last_line_array[1]}"
        password="${last_line_array[2]}"
        public_port_start="${last_line_array[3]}"
        public_port_end="${last_line_array[4]}"
        if [ -z "$public_port_start" ] || [ -z "$public_port_end" ]; then
            blue "Only the common version of the configuration batch repeat generation is supported, pure probe version or other can not be used"
            blue "仅支持普通版本的配置批量重复生成，纯探针版本或其他的无法使用"
            exit 1
        fi
        container_prefix="${container_name%%[0-9]*}"
        container_num="${container_name##*[!0-9]}"
        yellow "Current information on the last container:"
        yellow "目前最后一个小鸡的信息："
        blue "容器前缀-Prefix: $container_prefix"
        blue "容器数量-num: $container_num"
        blue "SSH端口-ssh: $ssh_port"
#         blue "密码: $password"
        blue "外网端口起-portstart: $public_port_start"
        blue "外网端口止-portend: $public_port_end"
    else
        red "Log file does not exist."
        red "log文件不存在。"
        container_prefix="ex"
        container_num=0
        ssh_port=20000
        public_port_end=30000
    fi
    
}

build_new_containers(){
    while true; do
        green "How many more containers need to be generated? (Enter how many new containers to add):"
        reading "还需要生成几个小鸡？(输入新增几个小鸡)：" new_nums
        if [[ "$new_nums" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            yellow "Invalid input, please enter a positive integer."
            yellow "输入无效，请输入一个正整数。"
        fi
    done
    while true; do
        green "How much memory is allocated per container? (Memory size per container, enter 256 if 256MB of memory is required):"
        reading "每个小鸡分配多少内存？(每个小鸡内存大小，若需要256MB内存，输入256)：" memory_nums
        if [[ "$memory_nums" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            yellow "Invalid input, please enter a positive integer."
            yellow "输入无效，请输入一个正整数。"
        fi
    done
    while true; do
        green "What size hard disk is allocated for each container? (per container hard drive size, enter 1 if 1G hard drive is required):"
        reading "每个小鸡分配多大硬盘？(每个小鸡硬盘大小，若需要1G硬盘，输入1)：" disk_nums
        if [[ "$disk_nums" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            yellow "Invalid input, please enter a positive integer."
            yellow "输入无效，请输入一个正整数。"
        fi
    done
    while true; do
        green "What is the download speed limit per container? (If you need the limit to be 300Mbit, enter 300):"
        reading "每个小鸡下载速度限制多少？(若需要限制为300Mbit，输入300)：" input_nums
        if [[ "$input_nums" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            yellow "Invalid input, please enter a positive integer."
            yellow "输入无效，请输入一个正整数。"
        fi
    done
    while true; do
        green "What is the upload speed limit per container? (If you need the limit to be 300Mbit, enter 300):"
        reading "每个小鸡上传速度限制多少？(若需要限制为300Mbit，输入300)：" output_nums
        if [[ "$output_nums" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            yellow "Invalid input, please enter a positive integer."
            yellow "输入无效，请输入一个正整数。"
        fi
    done
    while true; do
        green "What is the system of each container? (Note that the incoming parameter is the system name + version number, e.g. debian11, ubuntu20, centos7):"
        reading "每个小鸡的系统是什么？(注意传入参数为系统名字+版本号，如：debian11、ubuntu20、centos7)：" system
        a="${system%%[0-9]*}"
        b="${system##*[!0-9.]}"
        output=$(lxc image list images:${a}/${b})
        if echo "$output" | grep -q "${a}/${b}"; then
            echo "Matching mirror exists"
            echo "匹配的镜像存在"
            break
        else
            echo "No matching image found, please execute"
            echo "lxc image list images:system name/version number"
            echo "Check if the corresponding image exists"
            echo "未找到匹配的镜像，请执行"
            echo "lxc image list images:系统名字/版本号"
            echo "查询是否存在对应镜像"
            yellow "输入无效，请输入一个存在的系统"
        fi
    done
    for ((i=1; i<=$new_nums; i++)); do
        container_num=$(($container_num + 1))
        container_name="${container_prefix}${container_num}"
        ssh_port=$(($ssh_port + 1))
        public_port_start=$(($public_port_end + 1))
        public_port_end=$(($public_port_start + 25))
        ./buildone.sh $container_name $memory_nums $disk_nums $ssh_port $public_port_start $public_port_end $input_nums $output_nums N $system
        cat "$container_name" >> log
        rm -rf $container_name
    done
}

pre_check
check_log
build_new_containers
green "Generating new chicks is complete"
green "生成新的小鸡完毕"
check_log
