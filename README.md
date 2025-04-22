# LXD

[![Hits](https://hits.spiritlhl.net/lxd.svg?action=hit&title=Hits&title_bg=%23555555&count_bg=%230eecf8&edge_flat=false)](https://hits.spiritlhl.net)

## 前言

缘由: https://t.me/spiritlhl/176

所以更推荐：https://github.com/oneclickvirt/incus

本项目于2024.03.01后仅提供有限的维护，非Ubuntu的宿主机建议搭建使用新项目 [incus](https://github.com/oneclickvirt/incus)

## 更新

2025.04.22

- 调整CDN轮询顺序为随机顺序，避免单个CDN节点压力过大
- 修复设置IPV6网络的时候，没有利用上cdn进行持久化映射设置
- 提取公共代码，减少重复逻辑，模块化代码方便维护
- 容器相关信息同时写入容器的config的user.description，方便web面板查看

[更新日志](CHANGELOG.md)

## 说明文档

国内(China)：

[https://virt.spiritlhl.net/](https://virt.spiritlhl.net/)

国际(Global)：

[https://www.spiritlhl.net/en/](https://www.spiritlhl.net/en/)

说明文档中 LXD 分区内容

自修补的容器镜像源

https://github.com/oneclickvirt/lxd_images

## 友链

VPS融合怪测评项目

https://github.com/oneclickvirt/ecs

https://github.com/spiritLHLS/ecs

## Sponsor

Thanks to [dartnode](https://dartnode.com/?via=server) for test support.

## Stargazers over time

[![Stargazers over time](https://starchart.cc/oneclickvirt/lxd.svg)](https://starchart.cc/oneclickvirt/lxd)
