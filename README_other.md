
- 如果需要在你要挂载的盘上开，则使用以下命令在执行```lxd init```之前挂载(且保证该盘之前未挂载，可使用```umount 盘的路径```取消挂载)

- 安装驱动

```bash
sudo apt-get install zfsutils-linux -y
```

- 存储池新建存储

```bash
sudo zpool create -f zfs-pool 你要挂载的盘的路径
sudo lxc storage create default zfs source=zfs-pool
```

- 上面设置盘名称为default

- 查看是否创建成功

```bash
sudo lxc storage list
```

- 查看挂载的路径

```bash
sudo lxc storage show default
```

- 如果挂载成功，则执行```lxd init```时不再创建新盘，也即在下面这个选项出现时填***no***再回车不用默认的选项

```
Do you want to configure a new storage pool? (yes/no) [default=yes]: 
```

之后的东西就得自己翻了，创建服务器时(lxd init ……)需要使用```--storage default```指定存储盘且无法在容器级层面上自定义硬盘大小了，也无法使用本仓库脚本
