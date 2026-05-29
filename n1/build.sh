#!/bin/bash
# N1 ImmortalWrt 旁路由固件构建脚本
# 文件路径：n1/build.sh

source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建arm64的rootfs.tar.gz"

# 定义所需安装的包列表
PACKAGES=""

# 原作者基础功能包
PACKAGES="$PACKAGES curl fdisk"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filebrowser-go-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

# 主题
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"

# TTYD 终端
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"

# SFTP 服务
PACKAGES="$PACKAGES openssh-sftp-server"

# 核心功能包
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-app-aria2 aria2 luci-i18n-aria2-zh-cn"

# Docker 条件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# Perl 基础库
PACKAGES="$PACKAGES perlbase-base perlbase-file perlbase-time perlbase-utf8 perlbase-xsloader"

# 晶晨宝盒
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-amlogic luci-i18n-amlogic-zh-cn"

# 排除：无线、PPPoE、IPv6、多余文件系统工具
PACKAGES="$PACKAGES \
-kmod-brcmfmac -wpad-basic-mbedtls -iw -iwinfo \
-luci-proto-wireless -libiwinfo-data -rpcd-mod-iwinfo -luci-app-wireless -luci-app-channel-analysis \
-ppp -ppp-mod-pppoe -kmod-ppp -kmod-pppoe -kmod-pppox -kmod-slhc -kmod-mppe -luci-proto-ppp \
-luci-proto-ipv6 -odhcp6c -odhcpd-ipv6only \
-btrfs-progs -dosfstools -e2fsprogs -mkf2fs -exfat-fsck -exfat-mkfs -ntfs3-mount"

# ======================================
# 【仅修复这里】Store 集成条件判断 + 安装包
# ======================================
if [ "$ENABLE_STORE" = "true" ]; then
    echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
    sh shell/prepare-packages.sh
    sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf
    # 强制安装 Store 核心包（解决不显示问题）
    PACKAGES="$PACKAGES luci-app-store luci-lib-taskd luci-lib-xterm"
fi

PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ============ OpenClash 组件集成 ============
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

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
