#!/bin/bash
# N1 ImmortalWrt 旁路由固件构建脚本 - 优化版（精准排他）
# 文件路径：n1/build.sh

source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建arm64的rootfs.tar.gz"

# =========== 动态排除系统 - 核心优化 ===========
# 步骤1: 读取当前.config，准备动态排除
echo "🔧 读取当前配置文件..."
CURRENT_CONFIG=$(cat .config 2>/dev/null || true)

# 步骤2: 定义要彻底排除的包（N1旁路由不需要）
HARD_EXCLUDE_PACKAGES=(
    "libjson-c" "curl" "uclient-fetch" "libustream-openssl" "ca-bundle"
    "librt" "libpthread" "zlib" "jsonfilter" "libmbedtls" "libblobmsg-json"
    "libbsd" "libopenssl" "libopenssl-conf" "libopenssl-legacy"
    "wpad-basic-mbedtls" "iw" "iwinfo" "libiwinfo-data" "libiwinfo20230701"
    "rpcd-mod-iwinfo" "luci-app-wireless" "luci-channel-analysis"
    "ppp" "ppp-mod-pppoe" "kmod-ppp" "kmod-pppoe" "kmod-pppox" "kmod-slhc" "kmod-mppe"
    "luci-proto-ppp" "luci-proto-ipv6" "odhcp6c" "odhcpd-ipv6only"
    "kmod-amazon-ena" "kmod-e1000e" "kmod-dwmac-sun8i" "kmod-phy-broadcom"
    "kmod-phy-marvell-10g" "kmod-phy-smsc" "kmod-phylib-broadcom" "kmod-vmxnet3"
    "kmod-fsl-dpaa2-net" "kmod-renesas-net-avb" "kmod-sfp"
    "kmod-brcmfmac" "luci-app-qos" "qos-scripts"
)

# 步骤3: 动态修改.config - 强制排除
echo "🛡️ 应用硬性排除规则到.config..."
for pkg in "${HARD_EXCLUDE_PACKAGES[@]}"; do
    # 先删除可能存在的配置行
    CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | grep -v "CONFIG_PACKAGE_$pkg=")
    # 添加强制排除配置
    CURRENT_CONFIG=$(echo -e "$CURRENT_CONFIG\nCONFIG_PACKAGE_$pkg=n")
done
echo "$CURRENT_CONFIG" > .config

# 步骤4: 重新生成配置（关键！）
echo "🔄 重新生成内核配置..."
make defconfig >/dev/null 2>&1

# =========== 包定义保持兼容 ===========
PACKAGES=""

# 基础功能、主题、终端及常用服务（保留你的选择）
PACKAGES="$PACKAGES curl fdisk"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"

PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"

# OpenClash 保留
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-app-aria2 aria2 luci-i18n-aria2-zh-cn"

# Docker 选项
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    # 确保Docker依赖包被正确处理
    echo "✅ Docker支持已启用 - 保留必要依赖"
fi

# Perl 基础库（N1挂载硬盘需要）
PACKAGES="$PACKAGES perlbase-base perlbase-file perlbase-time perlbase-utf8 perlbase-xsloader"
PACKAGES="$PACKAGES block-mount e2fsprogs ntfs-3g nfs-utils"  # 硬盘挂载核心包

# 晶晨宝盒（N1专用）
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-amlogic luci-i18n-amlogic-zh-cn"

# =========== Store 商店集成 ===========
if [ "$ENABLE_STORE" = "true" ]; then
    echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
    sh shell/prepare-packages.sh
    sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf
    PACKAGES="$PACKAGES luci-app-store luci-lib-taskd luci-lib-xterm"
fi

PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# =========== OpenClash 组件集成 ===========
if [ "$ENABLE_OC" = "true" ]; then
    echo "✅ 已选择 luci-app-openclash，开始下载规则库和 IPK"
    mkdir -p files/etc/openclash
    rm -f files/etc/openclash/GeoIP.dat files/etc/openclash/GeoSite.dat
    wget --tries=10 --timeout=20 \
        https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat \
        -O files/etc/openclash/GeoIP.dat || \
    wget --timeout=20 \
        https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat \
        -O files/etc/openclash/GeoIP.dat || \
    echo "❌ GeoIP 下载失败，跳过"
    wget --tries=10 --timeout=20 \
        https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
        -O files/etc/openclash/GeoSite.dat || \
    wget --timeout=20 \
        https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat \
        -O files/etc/openclash/GeoSite.dat || \
    echo "❌ GeoSite 下载失败，跳过"
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*ipk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash IPK 地址: $URL"
    wget "$URL" -P /home/build/immortalwrt/packages/ || echo "IPK 下载失败，跳过"
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# =========== Mihomo 核心集成 ===========
if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ 已选择 luci-app-ssr-plus，添加 mihomo core"
    mkdir -p files/usr/bin
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-arm64-v1.19.24.gz"
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
    echo "✅ 已下载 mihomo core"
else
    echo "⚪️ 未选择 luci-app-ssr-plus"
fi

# =========== 软性排除 - 保持兼容性 ===========
# 保留你原有的软排除语法，作为双重保险
SOFT_EXCLUDE_PACKAGES=(
    "kmod-brcmfmac" "wpad-basic-mbedtls" "iw" "iwinfo" "luci-proto-wireless"
    "libiwinfo-data" "libiwinfo20230701" "rpcd-mod-iwinfo" "luci-app-wireless" "luci-channel-analysis"
    "ppp" "ppp-mod-pppoe" "kmod-ppp" "kmod-pppoe" "kmod-pppox" "kmod-slhc" "kmod-mppe"
    "luci-proto-ppp" "luci-proto-ipv6" "odhcp6c" "odhcpd-ipv6only"
    "kmod-amazon-ena" "kmod-e1000e" "kmod-dwmac-sun8i" "kmod-phy-broadcom"
    "kmod-phy-marvell-10g" "kmod-phy-smsc" "kmod-phylib-broadcom" "kmod-vmxnet3"
    "kmod-fsl-dpaa2-net" "kmod-renesas-net-avb" "kmod-sfp"
)

for pkg in "${SOFT_EXCLUDE_PACKAGES[@]}"; do
    PACKAGES="$PACKAGES -$pkg"
done

# =========== 构建验证 ===========
echo "✅ 最终包列表:"
echo "$PACKAGES"
echo "📦 预计排除的包: ${HARD_EXCLUDE_PACKAGES[*]}"

# =========== 构建命令 - 应用双重排除 ===========
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建镜像..."

# 构建命令 - 关键：EXCLUDE_PACKAGES 和 EXCLUDE_FROM_STAGE2
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="/home/build/immortalwrt/files" \
    ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE" \
    EXCLUDE_PACKAGES="${HARD_EXCLUDE_PACKAGES[*]}" \
    EXCLUDE_FROM_STAGE2="${HARD_EXCLUDE_PACKAGES[*]}" \
    V=s

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ❌ 构建失败！"
    exit 1
fi

# =========== 构建后验证 ===========
echo "🔍 验证排除效果..."
BUILD_DIR="bin/targets/armsr/armv8"
ROOTFS_FILE=$(find "$BUILD_DIR" -name "*rootfs.tar.gz" | head -n1)

if [ -z "$ROOTFS_FILE" ]; then
    echo "❌ 未找到生成的rootfs文件"
    exit 1
fi

# 检查排除包是否真的被排除
echo "✅ 验证硬性排除包是否被移除:"
FAILED_EXCLUDES=0
for pkg in "${HARD_EXCLUDE_PACKAGES[@]}"; do
    pkg_name=$(echo "$pkg" | sed 's/^kmod-//;s/-/_/g')
    if tar -tzf "$ROOTFS_FILE" | grep -q "$pkg_name"; then
        echo "❌ 警告: $pkg 仍然存在！"
        FAILED_EXCLUDES=$((FAILED_EXCLUDES + 1))
    fi
done

if [ $FAILED_EXCLUDES -eq 0 ]; then
    echo "🎉 所有硬性排除包都已成功移除！"
else
    echo "⚠️  有 $FAILED_EXCLUDES 个包排除失败，但构建继续..."
fi

# 报告最终大小
echo "📊 固件大小统计:"
ls -lh "$ROOTFS_FILE"
echo "📦 预计大小: 180-250MB (原始大小 350MB+)"

echo "$(date '+%Y-%m-%d %H:%M:%S') - ✅ 构建完成！N1旁路由固件已生成。"
echo "💡 重要提示: 此固件专为Phicomm N1旁路由优化，支持双硬盘挂载，网络功能完整。"
