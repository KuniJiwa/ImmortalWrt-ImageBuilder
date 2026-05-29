#!/bin/sh
# 文件路径：files/etc/uci-defaults/99-custom.sh
# 功能：N1 旁路由首次启动初始化
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 放开WAN口入站，新手友好
uci set firewall.@zone[1].input='ACCEPT'

# 安卓电视联网修复
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# ============ 旁路由网络初始化 ============
# 拆除默认网桥，单网口独立运行
for i in $(seq 1 10); do
    if ip link show eth0 > /dev/null 2>&1; then
        ip link set eth0 nomaster 2>/dev/null
        ip link delete br-lan 2>/dev/null
        ip link set eth0 up
        break
    fi
    sleep 1
done

# DHCP 自动获取 IP
uci set network.lan.proto='dhcp'
uci delete network.lan.ipaddr
uci delete network.lan.netmask
uci delete network.lan.gateway
uci delete network.lan.dns
uci commit network

# 关闭本机 DHCP 服务，避免和主路由冲突
uci set dhcp.lan.ignore='1'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true

# ============ 替换国内软件源 ============
cp /etc/opkg/distfeeds.conf /etc/opkg/distfeeds.conf.bak
sed -i 's|downloads.immortalwrt.org|mirrors.ustc.edu.cn/immortalwrt|g' /etc/opkg/distfeeds.conf

# 设置固件打包者信息
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='Packaged by KuniJiwa'/" /etc/openwrt_release

# ============ 移除 perl 依赖的定制脚本 ============
rm -f /usr/bin/cpustat
rm -f /usr/sbin/balethirq.pl
rm -f /usr/sbin/fixcpufreq.pl
rm -f /usr/bin/find_macaddr.pl
rm -f /usr/bin/inc_macaddr.pl
rm -f /usr/bin/get_random_mac.sh
rm -f /usr/bin/fix_wifi_macaddr.sh
# 清理 rc.local 里调用 perl 脚本的行
sed -i '/balethirq.pl/d' /etc/rc.local

# ============ 远程访问 ============
uci delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''
uci commit

# ============ Docker 防火墙（不装 Docker 则不触发） ============
if command -v dockerd >/dev/null 2>&1; then
  uci delete firewall.docker 2>/dev/null
  for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
    src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
    dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
    [ "$src" = "docker" ] || [ "$dest" = "docker" ] && uci delete firewall.@forwarding[$idx]
  done
  uci commit firewall

cat <<EOF >>/etc/config/firewall
config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'
config forwarding
  option src 'docker'
  option dest 'lan'
config forwarding
  option src 'docker'
  option dest 'wan'
config forwarding
  option src 'lan'
  option dest 'docker'
EOF
fi

echo "Init completed at $(date)" >>$LOGFILE
exit 0
