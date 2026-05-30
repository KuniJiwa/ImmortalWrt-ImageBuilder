#!/bin/bash
source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

# 基础包
PACKAGES=""
PACKAGES="$PACKAGES curl fdisk"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-app-openclash luci-app-aria2 aria2 luci-i18n-aria2-zh-cn"

# Docker
if [ "$INCLUDE_DOCKER" = "yes" ]; then
PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# Perl
PACKAGES="$PACKAGES perlbase-base perlbase-file perlbase-time perlbase-utf8 perlbase-xsloader"

# 晶晨宝盒
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-amlogic luci-i18n-amlogic-zh-cn"

# Store
if [ "$ENABLE_STORE" = "true" ]; then
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

# OpenClash 资源
if [ "$ENABLE_OC" = "true" ]; then
mkdir -p files/etc/openclash
wget --tries=10 --timeout=20 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
wget --tries=10 --timeout=20 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# ==============================================
# 🔥 核心：N1 深度驱动清洗（官方 armsr 专用）
# ==============================================
echo "==== 开始清洗非 N1 底层驱动 ===="
cd /home/build/immortalwrt

# 第一步：洗白官方配置，切断强依赖（关键！）
find target/linux/armsr/ -type f \( -name "*.yml" -o -name "Makefile" \) | while read -r file; do
  sed -i -E 's/kmod-(usb-net|rtl|rtw|mt|ath|amazon|amd|e1000|virtio|hyperv)[^ ]*//g' "$file"
  sed -i -E 's/kmod-(bnx|forcedeth|r8169|sis|via)[^ ]*//g' "$file"
done

# 第二步：驱动黑名单（强制剔除）
DROP_LIST=" \
-kmod-amazon-ena -kmod-e1000 -kmod-e1000e -kmod-virtio-net \
-kmod-hyperv-netvsc -kmod-tg3 -kmod-bnx2 -kmod-forcedeth \
-kmod-usb-net -kmod-usb-net-rtl8152 -kmod-rtw88 -kmod-mt76 \
-kmod-brcmfmac -wpad-basic-mbedtls -iw -iwinfo -luci-app-wireless \
-ppp -ppp-mod-pppoe -kmod-ppp -odhcp6c -odhcpd-ipv6only"

# 第三步：N1 必需驱动（强制保留）
N1_DRIVERS="kmod-dwmac-gxbb kmod-usb-core kmod-usb-storage block-mount fstools"

# 合并所有包
PACKAGES="$PACKAGES $DROP_LIST $N1_DRIVERS"

# 生效判断
EXCLUDE_LIST=$(echo "$PACKAGES" | tr ' ' '\n' | grep '^-' | tr '\n' '|')
[ -n "$EXCLUDE_LIST" ] && echo "✅排除生效|$EXCLUDE_LIST" || echo "❌排除未生效"

# 开始构建
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
echo "构建失败！"
exit 1
fi
echo "构建完成！"
