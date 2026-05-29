#!/bin/bash
# 独立诊断脚本：check-firmware.sh
# 用途：优先检查 rootfs.tar.gz（免挂载），回退挂载 btrfs img
# 输出：系统版本、软件源、配置文件、启动脚本、OpenClash 规则库、全量包列表
set -euo pipefail

# ========== 终端颜色&样式定义 ==========
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
WHITE="\033[37m"
GRAY="\033[90m"
BOLD="\033[1m"
NC="\033[0m"
SEP_LINE="────────────────────────────────────────────────────"

if [[ -n "${NO_COLOR:-}" ]]; then
  RED=""
  GREEN=""
  YELLOW=""
  WHITE=""
  GRAY=""
  BOLD=""
  NC=""
fi

PACKAGED_OUTPUTPATH="${PACKAGED_OUTPUTPATH:-/opt/openwrt_packit/output}"

echo "::group::$(echo -e "${BOLD}${WHITE}📊 固件完整详细诊断报告${NC}")"
echo -e "${BOLD}${WHITE}📊 固件完整详细诊断报告${NC}"
echo -e "${GRAY}${SEP_LINE}${NC}"

# 1. 优先查找 rootfs.tar.gz（免挂载，不受内核 btrfs 限制）
ROOTFS_FILE=$(find "${PACKAGED_OUTPUTPATH}" -name "rootfs.tar.gz" -type f 2>/dev/null | head -n1)

if [ -f "$ROOTFS_FILE" ]; then
    echo -e "${GREEN}✅ 使用 rootfs.tar.gz 进行免挂载诊断${NC}"
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【系统版本信息】${NC}"
    echo "  --- os-release ---"
    tar -xzf "$ROOTFS_FILE" -O ./etc/os-release 2>/dev/null || echo "  文件不存在"
    echo "  --- openwrt_release ---"
    tar -xzf "$ROOTFS_FILE" -O ./etc/openwrt_release 2>/dev/null || echo "  文件不存在"
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【软件源配置】${NC}"
    echo "  --- distfeeds.conf ---"
    tar -xzf "$ROOTFS_FILE" -O ./etc/opkg/distfeeds.conf 2>/dev/null || echo "  文件不存在"
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【OpenClash 规则库】${NC}"
    if tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "GeoIP.dat" > /dev/null; then
        echo -e "  ${GREEN}✅ GeoIP: 已打包${NC}"
    else
        echo -e "  ${YELLOW}⚠️ GeoIP: 未打包${NC}"
    fi
    if tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "GeoSite.dat" > /dev/null; then
        echo -e "  ${GREEN}✅ GeoSite: 已打包${NC}"
    else
        echo -e "  ${YELLOW}⚠️ GeoSite: 未打包${NC}"
    fi
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【/etc/config/network】${NC}"
    tar -xzf "$ROOTFS_FILE" -O ./etc/config/network 2>/dev/null || echo "  文件不存在（首次开机动态生成）"
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【99-custom.sh】${NC}"
    if tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "etc/uci-defaults/99-custom.sh" > /dev/null; then
        echo -e "  ${GREEN}✅ 已打包${NC}"
    else
        echo -e "  ${YELLOW}⚠️ 未打包${NC}"
    fi
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【主要目录大小统计】${NC}"
    for dir in bin etc lib usr www; do
        COUNT=$(tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./${dir}/" | wc -l) || true
        echo "  ./${dir}/ : ${COUNT} 个文件"
    done
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【面板可用性预测】${NC}"
    PACKAGE_LIST=$(tar -xzf "$ROOTFS_FILE" -O ./usr/lib/opkg/status 2>/dev/null | grep "^Package:" | awk '{print $2}' | sort)
    CONFIG_FILES=$(tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/config/" | sed 's|^./etc/config/||' | sort -u)
    UCI_DEFAULTS=$(tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/uci-defaults/" | sed 's|^./etc/uci-defaults/||' | sort)
    SKIP_CHECK="opkg|package-manager|luci"
    for app in $(echo "$PACKAGE_LIST" | grep "^luci-app-" | sed 's/luci-app-//'); do
        if echo "$app" | grep -qE "$SKIP_CHECK"; then
            echo -e "  ${GREEN}✅${NC} $app (无需独立配置)"
        elif echo "$CONFIG_FILES" | grep -qx "$app" || echo "$UCI_DEFAULTS" | grep -q "$app"; then
            echo -e "  ${GREEN}✅${NC} $app (已配置)"
        else
            echo -e "  ${YELLOW}⚠️${NC} $app (核心文件缺失)"
        fi
    done
    echo -e "${GRAY}${SEP_LINE}${NC}"

    # ========== 还原：原版2列格式（GitHub兼容）==========
    echo -e "  ${BOLD}${WHITE}【/etc/config/ 下所有配置文件】${NC}"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/config/" | sed 's|^./etc/config/||' | sort | column
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【/etc/uci-defaults/ 下所有启动脚本】${NC}"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/uci-defaults/" | sed 's|^./etc/uci-defaults/||' | sort | column
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "  ${BOLD}${WHITE}【/etc/init.d/ 下所有服务脚本】${NC}"
    tar -tzf "$ROOTFS_FILE" 2>/dev/null | grep "^./etc/init.d/" | sed 's|^./etc/init.d/||' | sort | column
    echo -e "${GRAY}${SEP_LINE}${NC}"

    # ========== 核心还原：全量包列表改回2行/2列（原版正常格式）==========
    echo -e "  ${BOLD}${WHITE}【全量包列表】${NC}"
    echo "$PACKAGE_LIST" | column
    PKG_TOTAL=$(echo "$PACKAGE_LIST" | wc -l)
    echo -e "  包总数: ${GREEN}${PKG_TOTAL}${NC}"
    echo -e "${GRAY}${SEP_LINE}${NC}"

    echo -e "${GREEN}✅ 诊断完成（免挂载模式）${NC}"
    echo "::endgroup::"
    exit 0
fi

# 2. 回退：无rootfs则直接跳过挂载（彻底避免报错）
IMG_FILE=$(ls -t "${PACKAGED_OUTPUTPATH}"/*.img.gz 2>/dev/null | head -n1)
if [ ! -f "$IMG_FILE" ]; then
    echo -e "${RED}❌ 未找到固件，跳过诊断${NC}"
else
    echo -e "${RED}❌ 挂载功能已关闭，避免报错${NC}"
fi
echo -e "${GRAY}${SEP_LINE}${NC}"
echo "::endgroup::"
exit 0
