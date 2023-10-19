# LXD

[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FspiritLHLS%2Flxd&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)

## 一键母鸡开小鸡

## 更新

2023.10.19

- 一键脚本支持自定义设置CPU限制数量，增加参数设置
- 尝试支持openwrt系统的SSH自动设置
- 重新划分SSH启用和设置密码的脚本，分为bash版本和sh版本
- 增加清华源备份源，确保当官方网站丢失和失联时使用第三方镜像源下载镜像

[更新日志](CHANGELOG.md)

## 待解决的问题

- LXC模板构建自定义的模板提前初始化好部分内容，避免原始模板过于干净导致初始化时间过长
- 部分机器的ubuntu22系统lxd开出的容器没网，待修复，此时建议回退ubuntu20
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
