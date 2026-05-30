#!/bin/bash
# N1 ImmortalWrt 旁路由固件构建脚本 - 精准排他修复版
# 文件路径：n1/build.sh

source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建arm64的rootfs.tar.gz"

# =========== 精准包定义 ===========
# 必须保留的核心包（N1旁路由必需）
CORE_PACKAGES="base-files ca-bundle libustream-mbedtls wget-ssl"

# 功能包（按需添加）
FEATURE_PACKAGES=""
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-i18n-diskman-zh-cn"  # 硬盘管理
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-i18n-package-manager-zh-cn"  # 软件管理
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-i18n-firewall-zh-cn"  # 防火墙
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-i18n-filemanager-zh-cn"  # 文件管理
FEATURE_PACKAGES="$FEATURE_PACKAGES fdisk e2fsprogs ntfs-3g"  # 硬盘工具
FEATURE_PACKAGES="$FEATURE_PACKAGES block-mount nfs-utils"  # 挂载支持

# 主题和终端
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-i18n-ttyd-zh-cn openssh-sftp-server"

# 必需插件
FEATURE_PACKAGES="$FEATURE_PACKAGES luci-app-amlogic luci-i18n-amlogic-zh-cn"  # N1专用

# 按条件添加的包
if [ "$ENABLE_STORE" = "true" ]; then
    echo "🔄 正在同步第三方软件仓库..."
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
    mkdir -p extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* extra-packages/
    sh shell/prepare-packages.sh
    sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf
    FEATURE_PACKAGES="$FEATURE_PACKAGES luci-app-store luci-lib-taskd luci-lib-xterm"
fi

if [ "$ENABLE_OC" = "true" ]; then
    echo "✅ 已启用 OpenClash"
    FEATURE_PACKAGES="$FEATURE_PACKAGES luci-app-openclash"
    # 规则库下载移到构建后处理
fi

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    echo "✅ 已启用 Docker"
    FEATURE_PACKAGES="$FEATURE_PACKAGES luci-i18n-dockerman-zh-cn"
fi

# =========== 精准排除列表（已测试有效的包名） ===========
# 使用 make image 命令支持的 -package 语法
EXCLUDE_PACKAGES=""
# 无线相关
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -kmod-brcmfmac -wpad-basic -iw -iwinfo -luci-proto-wireless"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -libiwinfo-data -libiwinfo20230701 -rpcd-mod-iwinfo"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -luci-app-wireless -luci-channel-analysis"
# PPPoE相关
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -ppp -ppp-mod-pppoe -kmod-ppp -kmod-pppoe -kmod-pppox"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -kmod-slhc -kmod-mppe -luci-proto-ppp"
# IPv6相关
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -odhcp6c -odhcpd-ipv6only -luci-proto-ipv6"
# 服务器网卡驱动
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -kmod-amazon-ena -kmod-e1000e -kmod-dwmac-sun8i"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -kmod-phy-broadcom -kmod-phy-marvell-10g"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -kmod-phy-smsc -kmod-phylib-broadcom -kmod-vmxnet3"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -kmod-fsl-dpaa2-net -kmod-renesas-net-avb -kmod-sfp"
# 冗余库
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -libjson-c -librt -libpthread -zlib -jsonfilter"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -libmbedtls -libblobmsg-json -libbsd"
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -libopenssl -libopenssl-conf -libopenssl-legacy"
# 其他无用包
EXCLUDE_PACKAGES="$EXCLUDE_PACKAGES -luci-app-qos -qos-scripts -luci-app-nlbwmon"

# =========== 构建命令（精准控制） ===========
echo "✅ 最终包列表:"
echo "核心包: $CORE_PACKAGES"
echo "功能包: $FEATURE_PACKAGES"
echo "排除包: $EXCLUDE_PACKAGES"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建镜像..."
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$CORE_PACKAGES $FEATURE_PACKAGES $EXCLUDE_PACKAGES" \
    FILES="files/" \
    ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE" \
    V=s

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ❌ 构建失败！"
    exit 1
fi

# =========== 构建后处理 ===========
# OpenClash规则库下载（构建成功后处理）
if [ "$ENABLE_OC" = "true" ]; then
    mkdir -p files/etc/openclash
    echo "✅ 下载OpenClash规则库..."
    wget --timeout=20 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat || \
    wget --timeout=20 https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat -O files/etc/openclash/GeoIP.dat
    
    wget --timeout=20 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat || \
    wget --timeout=20 https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# =========== 严格验证 ===========
echo "🔍 严格验证排除效果..."
ROOTFS_FILE=$(find bin/targets/armsr/armv8/ -name "*rootfs.tar.gz" | head -n1)

if [ -z "$ROOTFS_FILE" ]; then
    echo "❌ 未找到生成的rootfs文件"
    exit 1
fi

# 精确验证包是否被排除
VERIFY_FAILED=0
VERIFY_PACKAGES=(
    "curl" "librt.so" "libpthread.so" "libz.so" "jsonfilter"
    "libblobmsg_json.so" "libssl.so" "iw" "iwinfo" "ppp"
    "kmod-ppp" "kmod-pppoe" "odhcp6c" "odhcpd"
)

echo "✅ 检查以下包是否被排除:"
for pkg in "${VERIFY_PACKAGES[@]}"; do
    if tar -tzf "$ROOTFS_FILE" | grep -q "$pkg"; then
        echo "❌ 验证失败: $pkg 仍然存在"
        VERIFY_FAILED=1
    else
        echo "✅ 验证通过: $pkg 已排除"
    fi
done

if [ $VERIFY_FAILED -eq 1 ]; then
    echo "❌ 严格验证失败！构建终止。"
    ls -lh "$ROOTFS_FILE"
    exit 1
fi

# 报告最终大小
echo "📊 最终固件大小:"
ls -lh "$ROOTFS_FILE"
ACTUAL_SIZE=$(du -m "$ROOTFS_FILE" | cut -f1)
if [ "$ACTUAL_SIZE" -gt 200 ]; then
    echo "⚠️  警告: 固件大小 $ACTUAL_SIZE MB 超过预期 (目标 < 200MB)"
else
    echo "✅ 固件大小 $ACTUAL_SIZE MB 符合预期"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - ✅ 构建完成！N1旁路由固件已优化生成。"
