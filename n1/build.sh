#!/bin/bash
source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

# ==============================================
# 基础包（N1 必需，不包含任何多余驱动）
# ==============================================
PACKAGES=""
PACKAGES="$PACKAGES curl fdisk"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-app-aria2 aria2 luci-i18n-aria2-zh-cn"

# ==============================================
# OpenClash（按需）
# ==============================================
if [ "$ENABLE_OC" = "true" ]; then
    PACKAGES="$PACKAGES luci-app-openclash"
    # Perl 精简版（够用就行，不要全家桶）
    PACKAGES="$PACKAGES perl-www perlbase-base perlbase-utf8"
    
    # 规则下载（使用有效地址）
    mkdir -p files/etc/openclash
    # 改用 MetaCubeX 的仓库（Loyalsoldier 已归档）
    wget --tries=3 --timeout=10 https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat || true
    wget --tries=3 --timeout=10 https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat || true
fi

# ==============================================
# Docker（按需）
# ==============================================
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES docker docker-compose luci-i18n-dockerman-zh-cn"
fi

# ==============================================
# iStore 商店（按需）
# ==============================================
if [ "$ENABLE_STORE" = "true" ]; then
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
    sh shell/prepare-packages.sh
    # 添加架构支持
    echo "arch aarch64_generic 10" >> repositories.conf
    echo "arch aarch64_cortex-a53 15" >> repositories.conf
    PACKAGES="$PACKAGES luci-app-store luci-lib-taskd luci-lib-xterm"
fi

# ==============================================
# 晶晨宝盒
# ==============================================
PACKAGES="$PACKAGES luci-app-amlogic luci-i18n-amlogic-zh-cn"
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ==============================================
# 🔥 关键修复：排除冗余驱动（正确做法）
# ==============================================
echo "==== 【清洗】移除 N1 不需要的驱动 ===="

# 方法：直接排除，不依赖 sed 修改文件
# 注意：排除项必须放在包含项**之后**，且不要同时包含冲突的包
EXCLUDE_DRIVERS=" \
    -kmod-amazon-ena -kmod-e1000 -kmod-e1000e -kmod-virtio-net \
    -kmod-hyperv-netvsc -kmod-tg3 -kmod-bnx2 -kmod-forcedeth \
    -kmod-vmxnet3 -kmod-octeontx2-net -kmod-fsl-fec -kmod-mvpp2 \
    -kmod-usb-net -kmod-rtw88 -kmod-mt76 -kmod-brcmfmac \
    -wpad-basic-mbedtls -iw -iwinfo -luci-app-wireless \
    -ppp -ppp-mod-pppoe -kmod-ppp -odhcp6c -odhcpd-ipv6only \
    -dnsmasq -firewall -iptables -kmod-ipt-offload \
"

# N1 真正需要的驱动（armsr 默认已包含大部分，只需明确添加存储相关）
# 注意：不添加 kmod-usb-net 全家桶，按需添加具体芯片
N1_ESSENTIAL=""
# 如果需要外接 RTL8152 USB 网卡，取消下面注释
# N1_ESSENTIAL="$N1_ESSENTIAL kmod-usb-net-rtl8152"
# 如果需要外接 USB 硬盘
# N1_ESSENTIAL="$N1_ESSENTIAL kmod-usb-storage kmod-fs-ext4 kmod-fs-vfat"

# 最终组合：排除项在前，包含项在后（ImageBuilder 后覆盖前）
PACKAGES="$EXCLUDE_DRIVERS $PACKAGES $N1_ESSENTIAL"

# 打印最终排除列表
echo "✅ 排除项：$(echo "$EXCLUDE_DRIVERS" | tr ' ' '\n' | grep '^-' | tr '\n' ' ')"

# ==============================================
# 开始构建
# ==============================================
echo "开始构建固件..."
echo "最终包列表长度：$(echo $PACKAGES | wc -w) 个"

make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="files" \
    ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

if [ $? -ne 0 ]; then
    echo "❌ 固件构建失败"
    exit 1
fi

echo "✅ N1 固件构建完成"
