#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2026.04.06

# 一键卸载（交互式）：
# curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/lxduninstall.sh -o lxduninstall.sh && chmod +x lxduninstall.sh && bash lxduninstall.sh
#
# 一键卸载（无交互，环境变量预定义）：
# FORCE=true bash lxduninstall.sh
# FORCE=true REMOVE_STORAGE=true bash lxduninstall.sh
#
# 可用环境变量：
#   FORCE=true             跳过确认提示，直接执行卸载 / skip confirmation, uninstall directly
#   REMOVE_STORAGE=true    同时删除存储后端文件（loop 镜像）/ also remove backing storage files

cd /root >/dev/null 2>&1

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

FORCE_UPPER=$(printf '%s' "${FORCE:-}" | tr '[:lower:]' '[:upper:]')
REMOVE_STORAGE_UPPER=$(printf '%s' "${REMOVE_STORAGE:-}" | tr '[:lower:]' '[:upper:]')

# ─── 确认卸载 ────────────────────────────────────────────────────────────────
if [ "$FORCE_UPPER" != "TRUE" ]; then
    echo ""
    _red "======================================================"
    _red "  警告：此操作将彻底卸载 LXD 及相关所有组件！"
    _red "  WARNING: This will completely remove LXD and all"
    _red "           related components!"
    _red "  所有 LXC 容器和存储池数据将被永久销毁！"
    _red "  All LXC containers and storage pool data will be"
    _red "  PERMANENTLY DESTROYED!"
    _red "======================================================"
    echo ""
    reading "确认要继续？(y/n) [n] / Confirm continue? (y/n) [n]: " confirm
    confirm=${confirm:-n}
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        _yellow "已取消卸载。/ Uninstall cancelled."
        exit 0
    fi
    echo ""
    reading "是否同时删除存储后端文件（loop 镜像等）？(y/n) [n] / Also remove backing storage files? (y/n) [n]: " rs_input
    rs_input=${rs_input:-n}
    if [[ "$rs_input" =~ ^[yY]$ ]]; then
        REMOVE_STORAGE_UPPER="TRUE"
    fi
fi

_green "开始卸载 LXD... / Starting LXD uninstall..."
echo ""

# ─── 1. 停止并删除所有 LXC 容器 ──────────────────────────────────────────────
_blue "[1/9] 停止并删除所有 LXC 容器 / Stopping and deleting all LXC containers..."

if command -v lxc >/dev/null 2>&1 || [ -x /snap/bin/lxc ]; then
    LXC_CMD="lxc"
    ! command -v lxc >/dev/null 2>&1 && LXC_CMD="/snap/bin/lxc"

    containers=$($LXC_CMD list --format=csv -c n 2>/dev/null | awk -F',' '{print $1}' || true)
    if [ -n "$containers" ]; then
        while IFS= read -r ct; do
            [ -z "$ct" ] && continue
            _yellow "  正在停止 / Stopping: $ct"
            $LXC_CMD stop "$ct" --force 2>/dev/null || true
            _yellow "  正在删除 / Deleting: $ct"
            $LXC_CMD delete "$ct" --force 2>/dev/null || true
        done <<< "$containers"
        _green "  已删除所有容器 / All containers deleted."
    else
        _green "  无容器需要删除 / No containers found."
    fi
else
    _yellow "  lxc 命令不可用，跳过容器清理 / lxc not available, skipping container cleanup."
fi

# ─── 2. 清理 LXD 存储池 ──────────────────────────────────────────────────────
_blue "[2/9] 清理 LXD 存储池 / Cleaning up LXD storage pools..."

if command -v lxc >/dev/null 2>&1 || [ -x /snap/bin/lxc ]; then
    LXC_CMD="lxc"
    ! command -v lxc >/dev/null 2>&1 && LXC_CMD="/snap/bin/lxc"
    LXD_CMD="/snap/bin/lxd"

    # 获取存储类型和路径
    storage_type=""
    if [ -f /usr/local/bin/lxd_storage_type ]; then
        storage_type=$(cat /usr/local/bin/lxd_storage_type 2>/dev/null)
        _yellow "  检测到存储类型 / Detected storage type: $storage_type"
    fi

    # 尝试删除所有存储池中的卷
    pool_list=$($LXC_CMD storage list --format=csv 2>/dev/null | awk -F',' '{print $1}' || true)
    if [ -n "$pool_list" ]; then
        while IFS= read -r pool; do
            [ -z "$pool" ] && continue
            pool=$(echo "$pool" | tr -d '[:space:]')
            _yellow "  正在清空并删除存储池 / Cleaning pool: $pool"
            # 删除该池中的所有卷
            volumes=$($LXC_CMD storage volume list "$pool" --format=csv 2>/dev/null | awk -F',' '{print $2}' || true)
            if [ -n "$volumes" ]; then
                while IFS= read -r vol; do
                    [ -z "$vol" ] && continue
                    vol=$(echo "$vol" | tr -d '[:space:]')
                    $LXC_CMD storage volume delete "$pool" "$vol" 2>/dev/null || true
                done <<< "$volumes"
            fi
            # 从默认 profile 解除绑定
            $LXC_CMD profile device remove default root 2>/dev/null || true
            # 删除存储池
            $LXC_CMD storage delete "$pool" 2>/dev/null || true
        done <<< "$pool_list"
        _green "  存储池已清理 / Storage pools cleaned."
    else
        _green "  无存储池需要清理 / No storage pools found."
    fi

    # 清理 btrfs loop 挂载
    if [ "$storage_type" = "btrfs" ] || mountpoint -q /mnt/lxd_btrfs 2>/dev/null; then
        for mount_point in $(mount | grep btrfs | grep loop | awk '{print $3}'); do
            _yellow "  卸载 btrfs 挂载点 / Unmounting btrfs: $mount_point"
            umount "$mount_point" 2>/dev/null || true
        done
    fi

    # 清理 LVM vgroup
    if [ "$storage_type" = "lvm" ] && command -v vgremove >/dev/null 2>&1; then
        _yellow "  清理 LVM 卷组 / Removing LVM volume group: lxd_vg"
        vgremove -f lxd_vg 2>/dev/null || true
        # 清理 loop 设备
        for loop_dev in $(losetup -j /var/snap/lxd/common/lxd/disks/default.img 2>/dev/null | cut -d: -f1); do
            losetup -d "$loop_dev" 2>/dev/null || true
        done
    fi

    # 清理 ZFS pool
    if [ "$storage_type" = "zfs" ] && command -v zpool >/dev/null 2>&1; then
        _yellow "  清理 ZFS pool / Removing ZFS pool: lxd_zfs_pool"
        zpool destroy -f lxd_zfs_pool 2>/dev/null || true
    fi

    # 删除存储后端文件
    if [ "$REMOVE_STORAGE_UPPER" = "TRUE" ]; then
        _yellow "  删除存储后端 loop 文件 / Removing backing storage files..."
        # snap 默认存储目录下的镜像文件
        rm -f /var/snap/lxd/common/lxd/disks/default.img 2>/dev/null || true
        rm -f /var/snap/lxd/common/lxd/disks/*.img 2>/dev/null || true
        # 用户自定义路径下的 loop 文件（btrfs/lvm/zfs）
        for img in \
            /data/lxd-storage/btrfs_pool.img \
            /data/lxd-storage/lvm_pool.img \
            /data/lxd-storage/zfs_pool.img; do
            [ -f "$img" ] && rm -f "$img" && _yellow "  已删除 / Removed: $img"
        done
        # 通过记录的自定义路径查找
        if [ -f /usr/local/bin/lxd_storage_path ]; then
            sp=$(cat /usr/local/bin/lxd_storage_path 2>/dev/null)
            if [ -n "$sp" ] && [ -d "$sp" ]; then
                _yellow "  删除自定义存储目录 / Removing custom storage dir: $sp"
                rm -rf "$sp" 2>/dev/null || true
            fi
        fi
        _green "  存储后端文件已清理 / Backing storage files removed."
    fi
else
    _yellow "  lxc 命令不可用，跳过存储池清理 / lxc not available, skipping pool cleanup."
fi

# ─── 3. 卸载 LXD snap ────────────────────────────────────────────────────────
_blue "[3/9] 卸载 LXD snap / Removing LXD snap..."

if command -v snap >/dev/null 2>&1; then
    snap remove lxd 2>/dev/null && \
        _green "  LXD snap 已卸载 / LXD snap removed." || \
        _yellow "  LXD snap 不存在或卸载失败 / LXD snap not found or failed to remove."
else
    _yellow "  snap 不可用，跳过 / snap not available, skipping."
fi

# ─── 4. 卸载 check-dns 服务 ──────────────────────────────────────────────────
_blue "[4/9] 卸载 check-dns 服务 / Removing check-dns service..."

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop check-dns.service 2>/dev/null || true
    systemctl disable check-dns.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
fi
rm -f /etc/systemd/system/check-dns.service
_green "  check-dns 服务已移除 / check-dns service removed."

# ─── 5. 删除安装的文件 ───────────────────────────────────────────────────────
_blue "[5/9] 删除安装的文件 / Removing installed files..."

files_to_remove=(
    /usr/local/bin/ssh_bash.sh
    /usr/local/bin/ssh_sh.sh
    /usr/local/bin/config.sh
    /usr/local/bin/check-dns.sh
    /usr/local/bin/lxd_storage_type
    /usr/local/bin/lxd_storage_path
    /usr/local/bin/incus_tried_storage
    /usr/local/bin/incus_installed_storage
    /usr/local/bin/lxd_reboot
    /root/ssh_bash.sh
    /root/ssh_sh.sh
    /root/config.sh
)
for f in "${files_to_remove[@]}"; do
    [ -f "$f" ] && rm -f "$f" && _yellow "  已删除 / Removed: $f"
done
_green "  文件清理完成 / File cleanup done."

# ─── 6. 清理 iptables 规则 ───────────────────────────────────────────────────
_blue "[6/9] 清理防火墙规则 / Cleaning up firewall rules..."

# 清理 nftables 规则
if command -v nft >/dev/null 2>&1; then
    nft delete table inet lxd_nat 2>/dev/null || true
    nft delete table inet lxd_block 2>/dev/null || true
    nft delete table ip6 lxd_ipv6_nat 2>/dev/null || true
    nft list ruleset > /etc/nftables.conf 2>/dev/null || true
    _green "  nftables 规则已清理 / nftables rules cleaned."
fi

# 清理 iptables 规则
if command -v iptables >/dev/null 2>&1; then
    # 移除脚本添加的 MASQUERADE 规则（允许多条）
    while iptables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null; do :; done
    # 清理容器端口 FORWARD 规则（有屏蔽端口的 DROP 规则）
    for port in 3389 8888 54321 65432; do
        while iptables --ipv4 -D FORWARD -o eth0 -p tcp --dport "$port" -j DROP 2>/dev/null; do :; done
        while iptables --ipv4 -D FORWARD -o eth0 -p udp --dport "$port" -j DROP 2>/dev/null; do :; done
    done
    _green "  iptables 规则已清理 / iptables rules cleaned."
else
    _yellow "  iptables 不可用，跳过 / iptables not available, skipping."
fi

# ─── 7. 清理 /etc/fstab 中的 btrfs loop 行 ──────────────────────────────────
_blue "[7/9] 清理 /etc/fstab / Cleaning /etc/fstab..."

if [ -f /etc/fstab ]; then
    # 删除由本脚本添加的 btrfs loop 行（含 "btrfs loop" 的行）
    sed -i '/btrfs loop/d' /etc/fstab 2>/dev/null || true
    _green "  /etc/fstab 已清理 / /etc/fstab cleaned."
fi

# ─── 8. 还原 sysctl 设置 ─────────────────────────────────────────────────────
_blue "[8/9] 还原 sysctl 设置 / Restoring sysctl settings..."

for conf in /etc/sysctl.conf /etc/sysctl.d/99-custom.conf; do
    if [ -f "$conf" ]; then
        sed -i '/^net\.ipv4\.ip_forward=1/d' "$conf" 2>/dev/null || true
        _yellow "  已清理 / Cleaned: $conf"
    fi
done
# 移除仅由本脚本创建的空配置文件
[ -f /etc/sysctl.d/99-custom.conf ] && [ ! -s /etc/sysctl.d/99-custom.conf ] && \
    rm -f /etc/sysctl.d/99-custom.conf
sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
_green "  sysctl 设置已还原 / sysctl settings restored."

# ─── 9. 清理 /etc/security/limits.conf 和 logind.conf ───────────────────────
_blue "[9/9] 清理系统限制配置 / Cleaning system limits config..."

if [ -f /etc/security/limits.conf ]; then
    sed -i '/^\*[[:space:]]*hard[[:space:]]*nproc[[:space:]]*unlimited/d' /etc/security/limits.conf 2>/dev/null || true
    sed -i '/^\*[[:space:]]*soft[[:space:]]*nproc[[:space:]]*unlimited/d' /etc/security/limits.conf 2>/dev/null || true
fi
if [ -f /etc/systemd/logind.conf ]; then
    sed -i '/^UserTasksMax=infinity/d' /etc/systemd/logind.conf 2>/dev/null || true
fi
_green "  系统限制配置已清理 / System limits config cleaned."

echo ""
_green "======================================================"
_green "  LXD 卸载完成！/ LXD uninstall complete!"
_green "======================================================"
echo ""
_yellow "建议重启系统以确保所有更改生效。"
_yellow "It is recommended to reboot the system to apply all changes."
