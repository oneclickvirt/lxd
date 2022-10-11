# lxc

# 一键母鸡开小鸡

# -由频道 https://t.me/VPS_spiders 提供

同时进行TCP和UDP转发，除了SSH端口其他的映射内网外网端口一致，且只适用于Ubuntu或Debian，推荐Ubuntu20或Ubuntu更低版本，debian系列多半有问题

### 普通版本(带1个SSH端口，25个外网端口)

开出的小鸡配置：1核256MB内存1GB硬盘限速250MB

默认开swap：内存 = 1：1

自动关闭防火墙

```bash
apt update
apt install curl wget sudo dos2unix ufw -y
ufw disable
wget https://raw.githubusercontent.com/spiritLHLS/lxc/main/swap.sh
chmod 777 swap.sh
sudo ./swap.sh
apt install snapd -y
snap install lxd
/snap/bin/lxd init
```

![](https://i.bmp.ovh/imgs/2022/06/01/76dd73f43e138c88.png)

一般的选项回车默认即可

选择配置物理盘大小(提示默认最小1GB那个选项)，一般我填空闲磁盘大小减去内存大小后乘以0.95并向下取整

提示带auto的更新image的选项记得选no，避免更新占用

软连接lxc命令

```bash
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
```

测试lxc有没有软连接上

```
lxc -h
```

lxc命令无问题，执行初始化开小鸡，这一步最好放screen中后台挂起执行，开小鸡时长与你开几个和母鸡配置相关

下列命令最后一行为开小鸡名字前缀为**tj**的**10**个小鸡

```
# 初始化
rm -rf init.sh
wget https://github.com/spiritLHLS/lxc/raw/main/init.sh
chmod 777 init.sh
apt install dos2unix -y
dos2unix init.sh
./init.sh tj 10
```

有时候init.sh的运行路径有问题，此时建议前面加上sudo强制根目录执行

## 纯探针版本(只有一个SSH端口)

开出的小鸡配置：1核128MB内存300MB硬盘限速200MB

默认开swap：内存 = 1：1

自动关闭防火墙

```bash
apt update
apt install curl wget sudo dos2unix ufw -y
ufw disable
wget https://raw.githubusercontent.com/spiritLHLS/lxc/main/swap.sh
chmod 777 swap.sh
sudo ./swap.sh
apt install snapd -y
snap install lxd
/snap/bin/lxd init
```

![](https://i.bmp.ovh/imgs/2022/06/01/76dd73f43e138c88.png)

一般的选项回车默认即可

选择配置物理盘大小(提示默认最小1GB那行)，一般我填空闲磁盘大小减去内存大小后乘以0.95并向下取整

提示带auto的更新image的选项记得选no，避免更新占用

软连接lxc命令

```bash
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
```

测试lxc有没有软连接上

```
lxc -h
```

lxc命令无问题，执行初始化开小鸡，这一步最好放screen中后台挂起执行，开小鸡时长与你开几个和母鸡配置相关

下列命令最后一行为开小鸡名字前缀为**tj**的**10**个小鸡

```
# 初始化
rm -rf least.sh
wget https://github.com/spiritLHLS/lxc/raw/main/least.sh
chmod 777 least.sh
apt install dos2unix -y
dos2unix least.sh
./least.sh tj 10
```

有时候least.sh的运行路径有问题，此时建议前面加上sudo强制根目录执行

# 开完小鸡后，具体信息会生成在当前目录下的log文件中，格式 服务器名称 密码 ssh端口 外网端口起始 外网端口终止

### ps:原始用途是将频道测评剩余的VPS当母鸡开小鸡，避免浪费

对应的机器人

[@Status_of_Spiritlhl_Server_bot](https://t.me/Status_of_Spiritlhl_Server_bot)

分发母鸡开的小鸡，免费送点开出来的小鸡(免费服务器)(免费NAT服务器)

# 不要拿该脚本开出的小鸡当生产环境，lxc虚拟化不支持换内核，dd，开启bbr，探针鸡挂载warp等操作

本仓库不提供lxc虚拟化使用的其他问题的解答，非脚本相关问题请自行解决

虚拟小鸡想要查看是否在线

查看所有

```bash
lxc list
```

查看个例

```bash
lxc info 服务器名字
```

启动个例

```bash
lxc start 服务器名字
```

停止个例

```bash
lxc stop 服务器名字
```

删除个例

```bash
lxc rm -f 服务器名字
```
