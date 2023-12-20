# LXD

[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FspiritLHLS%2Flxd&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)

## 一键母鸡开小鸡

## 更新

2023.12.20

- 增加IPV6网络保活的定时任务，避免长期不使用导致V6的ndp广播缓存失效

[更新日志](CHANGELOG.md)

## 待解决的问题

- LXC模板构建自定义的模板提前初始化好部分内容并发布到自己的镜像仓库中，避免原始模板过于干净导致初始化时间过长，以及支持一些旧版本的系统(centos7，centos8，debian8，debian9)，相关资料[1](https://github.com/lxc/lxc-ci/tree/main/images)、[2](https://github.com/lxc/distrobuilder)、[3](https://cloud.tencent.com/developer/article/2348016?areaId=106001)
- 构建WIN的系统镜像，相关资料[1](https://www.microsoft.com/software-download/windows11), [2](https://discourse.ubuntu.com/t/how-to-install-a-windows-11-vm-using-lxd/28940), [3](https://help.aliyun.com/zh/simple-application-server/use-cases/use-vnc-to-build-guis-on-ubuntu-18-04-and-20-04#21e0b772d7fgc)
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
