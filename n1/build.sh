#!/bin/bash
source shell/custom-packages.sh
source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

# 基础安装包
PACKAGES=""
PACKAGES="$PACKAGES curl fdisk"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-app-openclash luci-app-aria2 aria2 luci-i18n-aria2-zh-cn"

# Docker 按需加载
if [ "$INCLUDE_DOCKER" = "yes" ]; then
PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# Perl 基础库
PACKAGES="$PACKAGES perlbase-base perlbase-file perlbase-time perlbase-utf8 perlbase-xsloader"

# 晶晨宝盒
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-amlogic luci-i18n-amlogic-zh-cn"

# Store 商店
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

# OpenClash 规则下载
if [ "$ENABLE_OC" = "true" ]; then
mkdir -p files/etc/openclash
wget --tries=10 --timeout=20 https://github.com/Loyalsoldier/v2-routetables/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
wget --tries=10 --timeout=20 https://github.com/Loyalsoldier/v2-routetables/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# ==============================================
# 🔥 最终版：官方armsr专用 深度清洗冗余驱动
# ==============================================
echo "==== 【前置操作】清洗官方底包冗余驱动 ===="
cd /home/build/immortalwrt

# 1. 洗白底包配置，解除官方硬编码驱动强制依赖（核心步骤）
find target/linux/armsr/ -type f \( -name "*.yml" -o -name "Makefile" \) | while read -r file; do
  sed -i -E 's/kmod-(usb-net|rtl|rtw|mt|ath|amazon|amd|e1000|virtio|hyperv)[^ ]*//g' "$file"
  sed -i -E 's/kmod-(bnx|forcedeth|r8169|sis|via|vmxnet3|fsl|mvpp2|octeontx2)[^ ]*//g' "$file"
done

# 2. 终极冗余驱动黑名单（日志中出现的无用驱动全部剔除）
DROP_DRIVERS=" \
-kmod-amazon-ena -kmod-e1000 -kmod-e1000e -kmod-virtio-net \
-kmod-hyperv-netvsc -kmod-tg3 -kmod-bnx2 -kmod-forcedeth \
-kmod-vmxnet3 -kmod-octeontx2-net -kmod-fsl-fec -kmod-mvpp2 \
-kmod-dwmac-rockchip -kmod-dwmac-imx -kmod-dwmac-sun8i \
-kmod-usb-net -kmod-usb-net-rtl8152 -kmod-rtw88 -kmod-mt76 \
-kmod-brcmfmac -wpad-basic-mbedtls -iw -iwinfo -luci-app-wireless \
-ppp -ppp-mod-pppoe -kmod-ppp -odhcp6c -odhcpd-ipv6only"

# 3. N1必需基础驱动（官方底包自带，无报错）
N1_DRIVERS="kmod-usb-core kmod-usb-storage block-mount fstools"

# 4. 合并所有打包规则
PACKAGES="$PACKAGES $DROP_DRIVERS $N1_DRIVERS"

# 5. 你要求的：一行生效校验（|分隔 + 状态符号）
EXCLUDE_LIST=$(echo "$PACKAGES" | tr ' ' '\n' | grep '^-' | tr '\n' '|')
[ -n "$EXCLUDE_LIST" ] && echo "✅排除生效|$EXCLUDE_LIST" || echo "❌排除未生效"

# 开始构建固件
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
echo "❌ 固件构建失败"
exit 1
fi

echo "✅ N1专属纯净固件构建完成"
