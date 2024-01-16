if [[ $? -eq 0 ]]; then
  apt-get install -y linux-source
  source_file=$(find /usr/src/ -name 'linux-source-*' | sort -r | head -n 1)
  tar -xvf "$source_file" -C /usr/src/
  kernel_version=$(uname -r)
  kernel_major_version=$(echo "$kernel_version" | cut -d '.' -f 1-2)
  source_path="/usr/src/linux-source-$kernel_major_version"
  cd "$source_path"
  yes '' | make defconfig
  apt-get install -y libssl-dev libelf-dev
  config_path="${source_path}/.config"
  sudo sed -i 's/# CONFIG_MODULES is not set/CONFIG_MODULES=y/' "$config_path"
  yes '' | make -C "${source_path}" ARCH=$(uname -m) savedefconfig
  cp "${source_path}/defconfig" "$config_path"
  yes '' | make modules_prepare
  yes '' | make modules
  yes '' | make modules_install
  echo "为加载含zfs选项的内核，请重启加载内核"
  exit 1
fi


removezfs() {
    rm /etc/apt/sources.list.d/bullseye-backports.list
    rm /etc/apt/preferences.d/90_zfs
    sed -i "/$lineToRemove/d" /etc/apt/sources.list
    apt-get remove ${codename}-backports -y
    apt-get remove zfs-dkms zfs-zed -y
    apt-get update
}

# https://openzfs.github.io/openzfs-docs/Getting%20Started/
checkzfs() {
    if echo "$temp" | grep -q "'zfs' isn't available" && [[ $status == false ]]; then
        _green "zfs module call failed, trying to compile zfs module plus load kernel..."
        _green "zfs模块调用失败，尝试编译zfs模块加载入内核..."
        if [ $SYSTEM == "Debian" ]; then
            #   apt-get install -y linux-headers-amd64
            codename=$(lsb_release -cs)
            lineToRemove="deb http://deb.debian.org/debian ${codename}-backports main contrib non-free"
            echo "deb http://deb.debian.org/debian ${codename}-backports main contrib non-free" | sudo tee -a /etc/apt/sources.list && apt-get update
            #   apt-get install -y linux-headers-amd64
            install_package ${codename}-backports
            if grep -q "deb http://deb.debian.org/debian bookworm-backports main contrib" /etc/apt/sources.list.d/bookworm-backports.list && grep -q "deb-src http://deb.debian.org/debian bookworm-backports main contrib" /etc/apt/sources.list.d/bookworm-backports.list; then
                echo "已修改源"
            else
                echo "deb http://deb.debian.org/debian bookworm-backports main contrib" >/etc/apt/sources.list.d/bookworm-backports.list
                echo "deb-src http://deb.debian.org/debian bookworm-backports main contrib" >>/etc/apt/sources.list.d/bookworm-backports.list
                echo "Package: src:zfs-linux
Pin: release n=bookworm-backports
Pin-Priority: 990" >/etc/apt/preferences.d/90_zfs
            fi
        elif [ $SYSTEM == "Ubuntu" ]; then
            # deb http://archive.ubuntu.com/ubuntu <CODENAME> main universe
            codename=$(lsb_release -cs)
            lineToRemove="deb http://archive.ubuntu.com/ubuntu ${codename} main universe"
            echo "deb http://archive.ubuntu.com/ubuntu ${codename} main universe" | sudo tee -a /etc/apt/sources.list && apt-get update
        fi
        apt-get update
        apt-get install -y dpkg-dev linux-headers-generic linux-image-generic
        if [ $? -ne 0 ]; then
            apt-get install -y dpkg-dev linux-headers-generic linux-image-generic --fix-missing
        fi
        if [[ $? -ne 0 ]]; then
            status=false
            removezfs
            return
        else
            status=true
        fi
        apt-get install -y zfsutils-linux
        if [ $? -ne 0 ]; then
            apt-get install -y zfsutils-linux --fix-missing
        fi
        if [[ $? -ne 0 ]]; then
            status=false
            removezfs
            return
        else
            status=true
        fi
        apt-get install -y zfs-dkms
        if [ $? -ne 0 ]; then
            apt-get install -y zfs-dkms --fix-missing
        fi
        if [[ $? -ne 0 ]]; then
            status=false
            removezfs
            return
        else
            status=true
        fi
        _green "Please reboot the machine (perform a reboot reboot) and execute this script again to load the new kernel, after the reboot you will need to enter the configuration you need again"
        _green "请重启本机(执行 reboot 重启)再次执行本脚本以加载新内核，重启后需要再次输入你需要的配置"
        exit 1
    fi
}

checkzfs