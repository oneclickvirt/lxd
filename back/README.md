# 测试命令，勿要使用

```
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/config.sh -o config.sh && chmod +x config.sh && bash config.sh
```


# 目录

* [配置要求](#配置要求)
   * [脚本检测](#脚本检测)
* [手动安装](#手动安装)
    * [普通版本](#普通版本)
        * [关闭防火墙](#关闭防火墙)
        * [开设虚拟内存SWAP](#开设虚拟内存SWAP)
        * [安装LXD](#安装LXD)
        * [多次批量生成LXC虚拟化的小鸡](#多次批量生成LXC虚拟化的小鸡)
    * [纯探针版本](#纯探针版本)
    * [查看log文件](#查看log文件)
    * [注意事项](#注意事项)
* [一键脚本老手推荐方便快捷](#一键脚本老手推荐方便快捷)
    * [一键安装lxd环境](#一键安装lxd环境)
    * [只开一个NAT服务器](#只开一个NAT服务器)
    * [其他配置个人使用可忽略](#其他配置个人使用可忽略)
      * [自动配置IPV6地址](#自动配置IPV6地址)
      * [屏蔽容易被滥用的端口的出入流量以屏蔽端口和屏蔽滥用工具包](#屏蔽容易被滥用的端口的出入流量以屏蔽端口和屏蔽滥用工具包)
      * [使用screen配置监控屏蔽某些进程的执行遇到某些进程的出现直接关闭容器](#使用screen配置监控屏蔽某些进程的执行遇到某些进程的出现直接关闭容器)
      * [一键安装开lxd母鸡所需要的带vnstat环境的常用预配置环境](#一键安装开lxd母鸡所需要的带vnstat环境的常用预配置环境)
      * [一键安装母鸡可视化操作的面板](#一键安装母鸡可视化操作的面板)
* [致谢](#致谢)
* [友链](#友链)

## 配置要求

硬件要求:
- 系统：Debian 8+, Ubuntu 18+(推荐)，系统越新越好
- 架构：推荐KVM、VMWARE虚拟化
- 内存：内存至少512MB
- 硬盘：硬盘(系统盘)至少10G
- 网络：独立的IPV4地址，IPV6可有可无，带宽能下载脚本就行，网络能连接Github的raw页面就行

PS: 如果硬件非常好资源很多，可使用PVE批量开KVM虚拟化的虚拟机 [跳转](https://github.com/spiritLHLS/pve)

PS: 如果硬件资源更烂，虚拟化不支持，可使用docker版本的，适配面更广 [跳转](https://github.com/spiritLHLS/docker)

### 脚本检测

**使用后续脚本的务必执行本命令检测母鸡是否符合要求**

```
bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/pre_check.sh)
```

#### 项目特点
<details>

- 本套脚本开发使用的Ubuntu20，Ubuntu别的长期维护版本应该也没问题，Debian无法使用zfs时自动切换别的存储类型

- 已设置同时进行TCP和UDP转发，除了SSH端口其他的映射内网外网端口一致

- 已设置支持开出的LXC容器进行docker嵌套虚拟，默认普通版本和纯探针版本使用debian11系统

- 已屏蔽容器内可能用于滥用的工具包和IPV4网络的TCP/UDP协议的端口( 3389 8888 54321 65432 )，以防止容器被用于扫描和爆破，且可外置进程检查有问题自动停机

- 已支持一键为LXC容器配置IPV6地址(前提是母鸡有IPV6子网，无IPV6地址则不配置)

- 一定要在 ```/root``` 的路径下运行本仓库脚本，且使用```一键脚本```的**不要删除**路径下的```ssh.sh```和```config.sh```文件

- 保证你要开的盘为默认的系统盘(sda或者sda1)而不是挂载的盘(sdb之类的)，不确定的使用```fdisk -l```和```df```查看

- 挂载其他盘的详看 [其他说明](https://github.com/spiritLHLS/lxc/blob/main/README_other.md)

- 一键脚本支持自定义限制所有内容，普通版本支持多次运行批量生成不覆盖先前生成的配置

</details>

## 手动安装

新手推荐，避免有bug不知道怎么修
- 批量生成NAT服务器
- 支持批量重复生成(多次批量开NAT服务器，且不覆盖原配置)
- 批量重复生成仅限于普通版本的配置，不支持纯探针版本

### 普通版本

(带1个SSH端口，25个外网端口)

开出的小鸡配置：1核256MB内存1GB硬盘限速250Mbps带宽

#### 关闭防火墙

```bash
apt update
apt install curl wget sudo dos2unix ufw jq -y
ufw disable
```

#### 开设虚拟内存SWAP

内存看你开多少小鸡，这里如果要开8个，换算需要2G内存，实际内存如果是512MB内存，还需要开1.5G，保守点开2G虚拟内存即可

执行下面命令，输入1，再输入2048，代表开2G虚拟内存

```
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/swap.sh -o swap.sh && chmod +x swap.sh && bash swap.sh
```

#### 安装LXD

实际swap开的虚拟内存应该是实际内存的2倍，也就是开1G是合理的，上面我描述的情况属于超开了

```
apt install snapd -y
snap install lxd
/snap/bin/lxd init
```

如果上面的命令中出现下面的错误

(snap "lxd" assumes unsupported features: snapd2.39 (try to update snapd and refresh the core snap))

使用命令修补后再进行lxd的安装

```
snap install core
```

如果无异常，上面三行命令执行结果如下

![图片](https://user-images.githubusercontent.com/103393591/233270028-5a43d0f7-45f5-4175-969e-d4d182cb877a.png)

一般的选项回车默认即可

选择配置物理盘大小(提示默认最小1GB那个选项)，一般我填空闲磁盘大小减去内存大小后乘以0.95并向下取整，这里我填了10GB

提示带auto的更新image的选项记得选no，避免更新占用系统

测试lxc有没有软连接上

```
lxc -h
```

如果报错则执行以下命令软连接lxc命令

```bash
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
```

连接后再测试lxc命令是否有报错找不到

#### 手动批量生成LXC虚拟化的小鸡

(默认内存和硬盘大小)

lxc若命令无问题，执行初始化开小鸡，这一步最好放```screen```中后台挂起执行，开小鸡时长与你开几个和母鸡配置相关

执行下面命令加载开机脚本

```
rm -rf init.sh
wget https://github.com/spiritLHLS/lxc/raw/main/scripts/init.sh
chmod 777 init.sh
apt install dos2unix -y
dos2unix init.sh
```

下面命令为开小鸡名字前缀为**tj**的**10**个小鸡

```
./init.sh tj 10
```

有时候init.sh的运行路径有问题，此时建议前面加上sudo强制根目录执行

#### 多次批量生成LXC虚拟化的小鸡

可自定义内存和硬盘大小

有执行过上面的手动批量生成过也没问题，配置是继承的不覆盖

如果需要多次批量生成小鸡，可使用

```
curl -L https://github.com/spiritLHLS/lxc/raw/main/scripts/add_more.sh -o add_more.sh && chmod +x add_more.sh && bash add_more.sh
```

可多次运行批量生成小鸡，且继承前面已生成的部分在后面添加，可自定义内存和硬盘大小

### 纯探针版本

(只有一个SSH端口)
<details>

开出的小鸡配置：1核128MB内存300MB硬盘限速200Mbps带宽

关闭防火墙

```bash
apt update
apt install curl wget sudo dos2unix ufw jq -y
ufw disable
```

开设虚拟内存

内存看你开多少小鸡，这里如果要开10个，换算需要1G内存，实际内存如果是512MB内存，还需要开0.5G，保守点开1G虚拟内存即可

执行下面命令，输入1，再输入1024，代表开1G虚拟内存

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/swap.sh -o swap.sh && chmod +x swap.sh && bash swap.sh
```

实际swap开的虚拟内存应该是实际内存的2倍，也就是开1G是合理的，再多就超开了

```
apt install snapd -y
snap install lxd
/snap/bin/lxd init
```

如果上面的命令中出现下面的错误

(snap "lxd" assumes unsupported features: snapd2.39 (try to update snapd and refresh the core snap))

使用命令修补后再进行lxd的安装

```
snap install core
```

如果无异常，上面三行命令执行结果如下

![图片](https://user-images.githubusercontent.com/103393591/233270028-5a43d0f7-45f5-4175-969e-d4d182cb877a.png)

一般的选项回车默认即可

选择配置物理盘大小(提示默认最小1GB那行)，一般我填空闲磁盘大小减去内存大小后乘以0.95并向下取整

提示带auto的更新image的选项记得选no，避免更新占用

软连接lxc命令

```bash
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
```

测试lxc有没有软连接上

```
lxc -h
```

lxc命令无问题，执行初始化开小鸡，这一步最好放screen中后台挂起执行，开小鸡时长与你开几个和母鸡配置相关

加载开机脚本

```
rm -rf least.sh
wget https://github.com/spiritLHLS/lxc/raw/main/scripts/least.sh
chmod 777 least.sh
apt install dos2unix -y
dos2unix least.sh
```

下列命令最后一行为开小鸡名字前缀为**tj**的**10**个小鸡

```
./least.sh tj 10
```

有时候least.sh的运行路径有问题，此时建议前面加上sudo强制根目录执行

</details>

### 查看log文件

#### 开完小鸡后，具体信息会生成在当前目录下的log文件中，格式如下
<details>

```
1号服务器名称 密码 ssh端口 外网端口起始 外网端口终止
2号服务器名称 密码 ssh端口 外网端口起始 外网端口终止
```

如果想要查看，只需在当前目录执行以下命令打印log文件即可

```bash
cat log
```
  
</details>

### 注意事项

#### 不要拿该脚本开出的小鸡当生产环境，lxc虚拟化不支持换内核，dd，开启bbr，**纯探针版本**(普通版本无问题)挂载warp等操作
<details>

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
lxc delete -f 服务器名字
```

进入内部

```bash
lxc exec 服务器名字 /bin/bash
```

退出则输入```exit```回车即可

删除所有LXC容器

```
lxc list | awk '{print $2}' | grep -v "^$" | xargs -I {} lxc delete -f {}
```

在容器内执行删除无用日志

```
sudo apt-get autoremove
sudo apt-get clean
sudo find /var/log -type f -delete
sudo find /var/tmp -type f -delete
sudo find /tmp -type f -delete
sudo find /var/cache/apt/archives -type f -delete
```
  
</details>

## 一键脚本老手推荐方便快捷

- 环境要求：Ubuntu 18+(推荐)，Debian 8+(仅限x86_64架构)
- 只生成一个NAT服务器，可自定义限制所有内容

#### 一键安装lxd环境

##### 初始化LXC环境

**如果是全新的服务器，务必保证apt update和apt install curl都无问题再执行本脚本**

**且自开机起最好等待5分钟后再执行以下命令，避免系统默认设置中就执行了本脚本导致apt源卡死**

这里的虚拟内存是说要开的SWAP大小，存储池则是你所有要开的小鸡占的盘的大小的总和

**如果是Debian系统的母鸡，务必在screen中执行本脚本，避免长期运行时SSH中断导致ZFS编译安装失败**

环境安装过程中可能需要重启服务器再次执行以加载含zfs的内核

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh && bash lxdinstall.sh
```

例子：

如果系统盘除去已占用空间还有18G硬盘空余，想开2G虚拟内存(2048MB的SWAP)，15G的存储池，则依次输入```2048```和```15```

#### 只开一个NAT服务器

##### 下载开机脚本

- (***非必须***，如果你使用过一键安装LXD的命令，自动已下载对应的开机脚本，请忽略下面的命令)

```
rm -rf buildone.sh
wget https://ghproxy.com/https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/buildone.sh
chmod 777 buildone.sh
apt install dos2unix -y
dos2unix buildone.sh
```

##### 开NAT服务器

内存大小以MB计算，硬盘大小以GB计算，下载速度上传速度以Mbit计算，是否启用IPV6不一定要填Y或者N，没有这个参数也行

如果```外网起端口```和```外网止端口```都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意```不能为空```，不进行映射需要设置为0

支持自定义小鸡的系统，注意传入参数为系统名字+版本号，如：debian11、ubuntu20，centos7，注意都是小写字母+数字的组合

```
./buildone.sh 小鸡名称 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N) 系统(留空则为debian11)
```

示例

```
./buildone.sh test 256 2 20001 20002 20025 300 300 N
```

这样就是创建一个名为test的小鸡，内存256MB，硬盘2G，SSH端口20001，内外网起止端口20002~20025，下载和上传速度都设置为300Mbit，且不自动设置外网IPV6地址，留空系统默认使用debian11

如果已通过以上方法生成过小鸡，还需要批量生成小鸡，可使用手动安装部分的脚本

但注意先删除测试小鸡再进行批量生成小鸡

```
lxc delete -f test
rm -rf test
ls
```

需要查看信息则执行

```
cat 小鸡名字
```

### 其他配置个人使用可忽略

- **以下的配置安装会加重母鸡的负担，非必要不要安装**

##### 自动配置IPV6地址

- (***非必须***，不使用的也没问题)
- **该脚本仅适用于母鸡有给```IPV6```子网且是```/64```的，且母鸡绑定了子网的```第一个IP```做```母鸡的IPV6地址或IPV6的gateway```**
- 自动为LXD创建的LXC容器配置```IPV6```地址
- 已集成到```buildone.sh```中可使用变量控制且无需事先下载，该脚本可不手动使用，在使用```buildone.sh```时配置Y开启即可

下载脚本

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/build_ipv6_network.sh -o build_ipv6_network.sh && chmod +x build_ipv6_network.sh
```

自动为容器配置IPV6映射地址

```bash
bash build_ipv6_network.sh 容器名称
```

映射完毕会打印信息

示例(给test容器自动配置IPV6地址，配置完成会写入一个test_v6的文件信息)

```bash
bash build_ipv6_network.sh test
```

删除所有IPV6已映射的规则

```bash
ip6tables -t nat -F PREROUTING
ip6tables-legacy -t nat -F PREROUTING
ip6tables-save > /etc/iptables/rules.v6
netfilter-persistent save
netfilter-persistent reload
service netfilter-persistent restart
```

卸载IPV6地址绑定的守护进程和对应的文件

```
systemctl stop add-ipv6.service
systemctl disable add-ipv6.service
rm /etc/systemd/system/add-ipv6.service
systemctl daemon-reload
rm /usr/local/bin/add-ipv6.sh
```

##### 屏蔽容易被滥用的端口的出入流量以屏蔽端口和屏蔽滥用工具包

- (***非必须***，该脚本仅仅是为了防止容器滥用方便，不装的也没问题)
- 事前预防

```
curl -L https://github.com/spiritLHLS/lxc/raw/main/scripts/rules.sh -o rules.sh && chmod +x rules.sh && bash rules.sh
```

##### 使用screen配置监控屏蔽某些进程的执行遇到某些进程的出现直接关闭容器

- 如需停止监控可使用```screen```命令停止```lxc_moniter```这个名字的窗口并删除
- (***非必须***，该脚本仅仅是为了防止容器滥用方便，不装的也没问题)
- 事后停机

```
curl -L https://github.com/spiritLHLS/lxc/raw/main/scripts/build_monitor.sh -o build_monitor.sh && chmod +x build_monitor.sh && bash build_monitor.sh
```

##### 一键安装开lxd母鸡所需要的带vnstat环境的常用预配置环境

- (***非必须***，该脚本仅仅是为了站点对接监控方便，不装的也没问题)

```
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/backend.sh -o backend.sh && chmod +x backend.sh && bash backend.sh
```

##### 一键安装母鸡可视化操作的面板

- (***非必须***，该面板只是为了方便可视化操作，没有也没问题)
- 原作者仓库：[跳转](https://github.com/turtle0x1/LxdMosaic)

```
lxc config set core.https_address [::]
lxc config set core.trust_password some-secret-string
snap install lxdmosaic
```

安装完毕后打开母鸡IP地址，按照提示设置admin的密码，其他一路默认就能使用面板了

### 致谢

https://github.com/lxc/lxd

https://lxdware.com/

https://discuss.linuxcontainers.org/

https://discuss.linuxcontainers.org/t/how-to-run-docker-inside-lxc-container/13017/4

https://discuss.linuxcontainers.org/t/error-seccomp-notify-not-supported-on-container-start/15038/3

https://discuss.linuxcontainers.org/t/how-do-i-assign-a-public-ipv6-address-to-a-lxc-container/6028

https://github.com/turtle0x1/LxdMosaic

https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/index.html

感谢 [@Ella-Alinda](https://github.com/Ella-Alinda) [@fscarmen](https://github.com/fscarmen) 提供的指导

