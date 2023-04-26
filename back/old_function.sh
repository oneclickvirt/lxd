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
