#!/bin/bash
# 独立诊断脚本：check-firmware.sh
# 用途：优先检查 rootfs.tar.gz（免挂载），回退挂载 btrfs img
# 输出：全量包列表、系统版本、配置文件、启动脚本、Aria2 配置、OpenClash 规则库
set -euo pipefail

PACKAGED_OUTPUTPATH="${PACKAGED_OUTPUTPATH:-/opt/openwrt_packit/output}"

echo "::group::📊 固件完整详细诊断报告"

# 1. 优先查找 rootfs.tar.gz（免挂载，不受内核 btrfs 限制）
ROOTFS_FILE=$(find "${PACKAGED_OUTPUTPATH}" -name "*-rootfs.tar.gz" -type f 2>/dev/null | head -n1)

if [ -f "$ROOTFS_FILE" ]; then
    echo "✅ 使用 rootfs.tar.gz 进行免挂载诊断"

    echo "【系统版本信息】"
    echo "--- os-release ---"
    tar -xzf "$ROOTFS_FILE" -O ./etc/os-release 2>/dev/null || echo "  文件不存在"
    echo "--- openwrt_release ---"
    tar -xzf "$ROOTFS_FILE" -O ./etc/openwrt_release 2>/dev/null || echo "  文件不存在"
    echo "******"

    echo "【软件源配置】"
    echo "--- distfeeds.conf ---"
    tar -xzf "$ROOTFS_FILE" -O ./etc/opkg/distfeeds.conf 2>/dev/null || echo "  文件不存在"
    echo "******"

    echo "【全量包列表】"
    PACKAGE_LIST=$(tar -xzf "$ROOTFS_FILE" -O ./usr/lib/opkg/status 2>/dev/null | grep "^Package:" | awk '{print $2}' | sort)
    echo "$PACKAGE_LIST"
    echo ""
    echo "包总数: $(echo "$PACKAGE_LIST" | wc -l)"
    echo "******"

    echo "【已安装的核心插件】"
    echo "$PACKAGE_LIST" | grep -E "luci-app-|aria2|openclash|ttyd|filebrowser|argon" || echo "  (未检测到关键插件)"
    echo "******"

    echo "【面板可用性预测】"
    CONFIG_FILES=$(tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/config/" | sed 's|^./etc/config/||' | sort -u)
    UCI_DEFAULTS=$(tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/uci-defaults/" | sed 's|^./etc/uci-defaults/||' | sort)
    SKIP_CHECK="opkg|package-manager|luci"
    for app in $(echo "$PACKAGE_LIST" | grep "^luci-app-" | sed 's/luci-app-//'); do
        if echo "$app" | grep -qE "$SKIP_CHECK"; then
            echo "  ✅ $app (无需独立配置)"
        elif echo "$CONFIG_FILES" | grep -qx "$app" || echo "$UCI_DEFAULTS" | grep -q "$app"; then
            echo "  ✅ $app (已配置)"
        else
            echo "  ⚠️ $app (核心文件缺失)"
        fi
    done
    echo "******"

    echo "【/etc/config/network】"
    tar -xzf "$ROOTFS_FILE" -O ./etc/config/network 2>/dev/null || echo "  文件不存在（首次开机动态生成）"
    echo "******"

    echo "【99-custom.sh】"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "etc/uci-defaults/99-custom.sh" > /dev/null && echo "  已打包" || echo "  未打包"
    echo "******"

    echo "【/etc/config/ 下所有配置文件】"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/config/" | sed 's|^./etc/config/||' | sort
    echo "******"

    echo "【/etc/uci-defaults/ 下所有启动脚本】"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/uci-defaults/" | sed 's|^./etc/uci-defaults/||' | sort
    echo "******"

    echo "【/etc/init.d/ 下所有服务脚本】"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/init.d/" | sed 's|^./etc/init.d/||' | sort
    echo "******"

    echo "【/etc/rc.local】"
    tar -xzf "$ROOTFS_FILE" -O ./etc/rc.local 2>/dev/null || echo "  文件不存在"
    echo "******"

    echo "【主要目录大小统计】"
    for dir in bin etc lib usr www; do
        COUNT=$(tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./${dir}/" | wc -l) || true
        echo "  ./${dir}/ : ${COUNT} 个文件"
    done
    echo "******"

    echo "【Aria2 配置文件】"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "etc/config/aria2" > /dev/null && echo "  Aria2 主配置: 已打包" || echo "  Aria2 主配置: 未打包"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "etc/aria2/" > /dev/null && echo "  Aria2 脚本: 已打包" || echo "  Aria2 脚本: 未打包"
    echo "******"

    echo "【OpenClash 规则库】"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "GeoIP.dat" > /dev/null && echo "  GeoIP: 已打包" || echo "  GeoIP: 未打包"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "GeoSite.dat" > /dev/null && echo "  GeoSite: 已打包" || echo "  GeoSite: 未打包"

    echo "::endgroup::"
    echo "✅ 诊断完成（免挂载模式）"
    exit 0
fi

# 2. 回退：如果没有 rootfs.tar.gz，尝试挂载 img
IMG_FILE=$(ls -t "${PACKAGED_OUTPUTPATH}"/*.img.gz 2>/dev/null | head -n1)
if [ ! -f "$IMG_FILE" ]; then
    echo "❌ 未找到固件，跳过诊断"
    echo "::endgroup::"
    exit 0
fi

TMPDIR=$(mktemp -d)
cleanup() {
    sudo umount /mnt/diag 2>/dev/null || true
    if [ -n "${LOOP_DEV:-}" ]; then
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    rm -rf "${TMPDIR:-}" 2>/dev/null
}
trap cleanup EXIT

gunzip -c "$IMG_FILE" > "$TMPDIR/firmware.img"

LOOP_DEV=$(sudo losetup -fP --show "$TMPDIR/firmware.img")
if ! sudo mount -o ro "${LOOP_DEV}p2" /mnt/diag 2>/dev/null; then
    echo "⚠️ 常规挂载失败，尝试修复 btrfs 元数据后重新挂载..."
    sudo btrfs check --readonly "${LOOP_DEV}p2" 2>/dev/null || true
    if ! sudo mount -o ro,recovery "${LOOP_DEV}p2" /mnt/diag 2>/dev/null; then
        echo "❌ 挂载最终失败，且无 rootfs.tar.gz 可回退，跳过诊断"
        exit 0
    fi
fi

# 挂载模式诊断
PACKAGE_LIST=$(cat /mnt/diag/usr/lib/opkg/status 2>/dev/null | grep "^Package:" | awk '{print $2}' | sort)
CONFIG_FILES=$(ls /mnt/diag/etc/config/ 2>/dev/null | sort -u)
UCI_DEFAULTS=$(ls /mnt/diag/etc/uci-defaults/ 2>/dev/null | sort)
PKG_TOTAL=$(echo "$PACKAGE_LIST" | wc -l)

echo ""
echo "📦 固件: $(basename "$IMG_FILE")"
echo "🕒 诊断时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "******"

echo "【系统版本信息】"
cat /mnt/diag/etc/os-release 2>/dev/null || echo "  文件不存在"
echo ""
cat /mnt/diag/etc/openwrt_release 2>/dev/null || echo "  文件不存在"
echo "******"

echo "【软件源配置】"
cat /mnt/diag/etc/opkg/distfeeds.conf 2>/dev/null || echo "  文件不存在"
echo "******"

echo "【全量包列表】"
echo "$PACKAGE_LIST"
echo ""
echo "包总数: $PKG_TOTAL"
echo "******"

echo "【已安装的核心插件】"
echo "$PACKAGE_LIST" | grep -E "luci-app-|aria2|openclash|ttyd|filebrowser|argon" || echo "  (未检测到关键插件)"
echo "******"

echo "【面板可用性预测】"
SKIP_CHECK="opkg|package-manager|luci"
for app in $(echo "$PACKAGE_LIST" | grep "^luci-app-" | sed 's/luci-app-//'); do
    if echo "$app" | grep -qE "$SKIP_CHECK"; then
        echo "  ✅ $app (无需独立配置)"
    elif echo "$CONFIG_FILES" | grep -qx "$app" || echo "$UCI_DEFAULTS" | grep -q "$app"; then
        echo "  ✅ $app (已配置)"
    else
        echo "  ⚠️ $app (核心文件缺失)"
    fi
done
echo "******"

echo "【/etc/config/network】"
cat /mnt/diag/etc/config/network 2>/dev/null || echo "  文件不存在（首次开机动态生成）"
echo "******"

echo "【99-custom.sh】"
ls /mnt/diag/etc/uci-defaults/99-custom.sh 2>/dev/null > /dev/null && echo "  已打包" || echo "  未打包"
echo "******"

echo "【/etc/config/ 下所有配置文件】"
echo "$CONFIG_FILES"
echo "******"

echo "【/etc/uci-defaults/ 下所有启动脚本】"
echo "$UCI_DEFAULTS"
echo "******"

echo "【/etc/init.d/ 下所有服务脚本】"
ls /mnt/diag/etc/init.d/ 2>/dev/null | sort
echo "******"

echo "【/etc/rc.local】"
cat /mnt/diag/etc/rc.local 2>/dev/null || echo "  文件不存在"
echo "******"

echo "【主要目录大小统计】"
for dir in bin etc lib usr www; do
    COUNT=$(find /mnt/diag/$dir -type f 2>/dev/null | wc -l) || true
    echo "  ./${dir}/ : ${COUNT} 个文件"
done
echo "******"

echo "【Aria2 配置文件】"
ls /mnt/diag/etc/config/aria2 2>/dev/null > /dev/null && echo "  Aria2 主配置: 已打包" || echo "  Aria2 主配置: 未打包"
ls /mnt/diag/etc/aria2/ 2>/dev/null > /dev/null && echo "  Aria2 脚本: 已打包" || echo "  Aria2 脚本: 未打包"
echo "******"

echo "【OpenClash 规则库】"
ls /mnt/diag/etc/openclash/GeoIP.dat 2>/dev/null > /dev/null && echo "  GeoIP: 已打包" || echo "  GeoIP: 未打包"
ls /mnt/diag/etc/openclash/GeoSite.dat 2>/dev/null > /dev/null && echo "  GeoSite: 已打包" || echo "  GeoSite: 未打包"

echo "::endgroup::"
echo "✅ 诊断完成（挂载模式）"
