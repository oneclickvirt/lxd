# 前言

如果脚本有任何问题或者任何修复系统的需求，可在issues中提出，有空会解决或者回答

# lxc 一键母鸡开小鸡

更新：

2023.06.14

- 修复IPV6地址绑定后如果重启宿主机会导致绑定丢失的问题
- 增加针对IPV6转发的IPV6地址绑定的守护进程，保证重启后IPV6的映射依然存在

[更新日志](CHANGELOG.md)

## 待解决的问题

使得母鸡支持更多的系统版本

## 说明文档

[virt.spiritlhl.net](https://virt.spiritlhl.net/)

### 友链

VPS融合怪测评脚本

https://github.com/spiritLHLS/ecs

朋友写的针对合租服务器使用的(需要有一定的LXD或LXC基础，否则你看不懂部分设置)(更新可能有点缓慢)

https://github.com/MXCCO/lxdpro

## Stargazers over time

[![Stargazers over time](https://starchart.cc/spiritLHLS/lxc.svg)](https://starchart.cc/spiritLHLS/lxc)
