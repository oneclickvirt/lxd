# LXD

[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FspiritLHLS%2Flxd&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)

## 一键母鸡开小鸡

## 更新

2023.09.02

- 增加宿主机的证书设置+vnstat环境安装+lxd环境安装的三合一脚本，配合LXD站点

[更新日志](CHANGELOG.md)

## 待解决的问题

- 开设的容器启用的IPV6地址目前是使用的iptables和add route手动连接的，应当替换为自动分配IPV6地址的ndppd进行连接，待修改
- LXC模板构建自定义的模板提前初始化好部分内容，避免原始模板过于干净导致初始化时间过长
- 部分机器的ubuntu22系统lxd开出的容器没网，待修复，此时建议回退ubuntu20
- 系统debian11做宿主机系统可能部分资源限制不住，待修复，此时建议回退ubuntu20([相关](https://github.com/spiritLHLS/lxd/issues/21#issue-1819109212))
- 开设的容器不支持centos7，centos8，仅支持centos的stream版本，待添加支持([相关](https://github.com/spiritLHLS/lxd/issues/20#issue-1816499383))
- 开设的容器不支持debian8，debian9，待添加支持([相关](https://github.com/spiritLHLS/lxd/issues/21#issue-1819109212))
- 使得宿主机支持更多的系统，不仅限于ubuntu和debian系做宿主机

## 说明文档

国内(China)：

[virt.spiritlhl.net](https://virt.spiritlhl.net/)

国际(Global)：

[www.spiritlhl.net](https://www.spiritlhl.net/)

说明文档中 LXD 分区内容

## 友链

VPS融合怪测评脚本

https://github.com/spiritLHLS/ecs

朋友写的针对合租服务器使用的(需要有一定的LXD或LXC基础，否则你看不懂部分设置)(更新可能有点缓慢)

https://github.com/MXCCO/lxdpro

## Stargazers over time

[![Stargazers over time](https://starchart.cc/spiritLHLS/lxd.svg)](https://starchart.cc/spiritLHLS/lxd)
