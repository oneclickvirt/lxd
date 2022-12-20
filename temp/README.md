一键修改本机所有LXC容器支持docker

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/temp/cus_all_sup_docker.sh -o cus_all_sup_docker.sh && chmod +x cus_all_sup_docker.sh && bash cus_all_sup_docker.sh
```

一键在debian镜像的lxc容器中安装docker环境

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/temp/debian_docker_support.sh -o debian_docker_support.sh && chmod +x debian_docker_support.sh && bash debian_docker_support.sh
```

测试doker是否安装成功

```bash
docker run hello-world
```
