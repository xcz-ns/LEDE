#!/bin/bash

# ==============================================================================
# 模块 1: 软件源管理 & 第三方软件包拉取
# ==============================================================================

# 切换 LEDE LuCI 源
sed -i 's/^\(src-git luci \).*/\1https:\/\/github.com\/coolsnowwolf\/luci.git;master/' feeds.conf.default
sed -i '/^#/d' feeds.conf.default

# 打印默认 feeds 配置
cat feeds.conf.default

git clone --depth 1 https://github.com/kenzok8/small-package small-package
cp -rf small-package/{luci-app-ramfree,luci-app-poweroff} package/

git clone --depth 1 https://github.com/OldCoding/luci-app-filebrowser package/luci-app-filebrowser
git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/lucky
git clone --depth 1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth 1 https://github.com/vernesong/OpenClash.git package/openclash \
    && mv package/openclash/luci-app-openclash package/ \
    && rm -rf package/openclash
git clone --depth 1 https://github.com/lisaac/luci-app-dockerman package/luci-app-dockerman

# 更新 feeds
./scripts/feeds update -a

# 删除冲突软件
rm -rf feeds/luci/applications/{luci-app-openclash,luci-app-filebrowser,luci-app-filebrowser-go,luci-app-dockerman,luci-app-ramfree,luci-app-poweroff}
rm -rf feeds/luci/themes/{luci-theme-argon,luci-theme-design}

# 安装 feeds
./scripts/feeds install -a -f

# ==============================================================================
# 模块 2: 系统基础配置 & 网络初始化 (UCI 定制)
# ==============================================================================

# 修改默认时间格式
sed -i 's#localtime  = os.date()#localtime  = os.date("%Y年%m月%d日") .. " " .. translate(os.date("%A")) .. " " .. os.date("%X")#g' package/lean/autocore/files/*/index.htm

# 定义配置文件路径
NET="package/base-files/files/bin/config_generate"
ZZZ="package/lean/default-settings/files/zzz-default-settings"

# 增加个性名称
sed -i "s/LEDE /Built on $(TZ=UTC-8 date "+%Y.%m.%d") By XCZNS /g" "$ZZZ"

# 设置主机名、设置 argon 主题
cat >> "$ZZZ" <<EOF
uci set system.@system[0].hostname='OpenWrt'
uci set luci.main.mediaurlbase=/luci-static/argon
uci commit
EOF

# filebrowser 设置密码
cat >> "$ZZZ" <<EOF
/usr/bin/filebrowser users update admin --database /etc/filebrowser.db --password ZYB18332894508
EOF

# 旁路由设置
cat >> "$ZZZ" << 'EOF'
# ================= 旁路由：清理默认 WAN 配置 =================
# 清理网络接口
uci delete network.wan 2>/dev/null
uci delete network.wan6 2>/dev/null

# 动态清理防火墙中所有关联 wan 或 wan6 的区域(zone)、转发(forwarding)和规则(rule)
while true; do
    sec=$(uci show firewall | grep -E "\.(name|src|dest)='wan6?'" | awk -F. '{print $2}' | head -n 1)
    [ -z "$sec" ] && break
    uci delete firewall."$sec"
done

# ================= 旁路由：网络配置 =================
# 配置 lan 接口
uci set network.lan=interface
uci set network.lan.type='bridge'
uci set network.lan.ifname='eth0'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.11.103'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.11.1'
uci delete network.lan.dns 2>/dev/null
uci add_list network.lan.dns='192.168.11.1'
uci set network.lan.delegate='0'
uci set network.lan.ip6assign='64'

# 配置 lanv6 接口
uci set network.lanv6=interface
uci set network.lanv6.proto='dhcpv6'
uci set network.lanv6.ifname='eth0'
uci set network.lanv6.reqaddress='try'
uci set network.lanv6.reqprefix='auto'
uci set network.lanv6.device='br-lan'

# ================= 旁路由：防火墙配置 =================
# 修改默认 lan 区域配置 (清理 wan 后,lan 通常就是 @zone[0])
uci set firewall.@zone[0].output='ACCEPT'
uci set firewall.@zone[0].forward='ACCEPT'
uci set firewall.@zone[0].masq='1'
uci set firewall.@zone[0].network='lan lanv6'
uci set firewall.@zone[0].input='REJECT'

# 1. 允许DHCP续租
uci add firewall rule
uci set firewall.@rule[-1].name='允许DHCP续租'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='68'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].family='ipv4'

# 2. 允许Ping
uci add firewall rule
uci set firewall.@rule[-1].name='允许Ping'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].target='ACCEPT'
uci add_list firewall.@rule[-1].icmp_type='echo-request'

# 3. 允许IGMP
uci add firewall rule
uci set firewall.@rule[-1].name='允许IGMP'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='igmp'
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].target='ACCEPT'

# 4. 允许DHCPv6
uci add firewall rule
uci set firewall.@rule[-1].name='允许DHCPv6'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='546'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'

# 5. 允许MLD
uci add firewall rule
uci set firewall.@rule[-1].name='允许MLD'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'
uci add_list firewall.@rule[-1].src_ip='fe80::/10'

# 6. 允许ICMPv6入站
uci add firewall rule
uci set firewall.@rule[-1].name='允许ICMPv6入站'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].limit='1000/sec'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'
for t in bad-header destination-unreachable echo-reply echo-request neighbour-advertisement neighbour-solicitation packet-too-big router-advertisement router-solicitation time-exceeded unknown-header-type; do
    uci add_list firewall.@rule[-1].icmp_type="$t"
done

# 7. 允许ICMPv6转发
uci add firewall rule
uci set firewall.@rule[-1].name='允许ICMPv6转发'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='*'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].limit='1000/sec'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'
for t in bad-header destination-unreachable echo-reply echo-request packet-too-big time-exceeded unknown-header-type; do
    uci add_list firewall.@rule[-1].icmp_type="$t"
done

# 8. 允许本地子网
uci add firewall rule
uci set firewall.@rule[-1].name='允许本地子网'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].target='ACCEPT'
uci add_list firewall.@rule[-1].proto='all'
uci add_list firewall.@rule[-1].src_ip='192.168.11.0/24'

uci commit network
uci commit firewall
EOF

# ------------------------------------------------------------------------------
# 二进制组件预集成 (OpenClash / Lucky / Filebrowser)
# ------------------------------------------------------------------------------
CONF="${WORKPATH}/${CUSTOM_SH}"
BIN_DIR="$BUILDER_DIR/openwrt/files/usr/bin"
CORE_DIR="$BUILDER_DIR/openwrt/files/etc/openclash/core"
ARCH_AMD64="amd64"
ARCH_X86_64="x86_64"

mkdir -p "$BIN_DIR" "$CORE_DIR"

# 1. OpenClash Meta 内核预集成
OPENCLASH_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-${ARCH_AMD64}.tar.gz"

if grep -q "^CONFIG_PACKAGE_luci-app-openclash=y" "$CONF"; then
    echo "----------------------------------------------------"
    echo "[1/3] 正在解析 OpenClash Meta 版本信息..."
    echo "✅ 成功匹配: $OPENCLASH_URL"
    echo "开始下载并提取二进制..."

    if wget -qO- --tries=3 --timeout=15 "$OPENCLASH_URL" \
        | tar -xz -C "$CORE_DIR"; then

        mv -f "$CORE_DIR/clash" "$CORE_DIR/clash_meta"
        chmod +x "$CORE_DIR/clash_meta"

        echo "🎉 完成：已成功提取到 $CORE_DIR/clash_meta"
        ls -lh "$CORE_DIR/clash_meta"
    else
        echo "❌ 下载或解压失败"
        exit 1
    fi
else
    echo "未启用 OpenClash，添加清理残留配置指令..."
    echo 'rm -rf /etc/openclash' >> "$ZZZ"
fi

# 2. 下载并配置 Filebrowser 二进制文件
FB_REPO="filebrowser/filebrowser"
FB_ARCH_KEY="linux-${ARCH_AMD64}-filebrowser.tar.gz"

echo "----------------------------------------------------"
echo "[2/3] 正在解析 Filebrowser 版本信息..."

# 优先通过 GitHub API 解析下载地址
FB_URL=$(curl -sL "https://api.github.com/repos/$FB_REPO/releases/latest" \
    | grep -o "https://[^\"]*${FB_ARCH_KEY}" \
    | head -n 1)

# API 达到调用限制时的回退解析方案
if [ -z "$FB_URL" ]; then
    LATEST_TAG=$(curl -sIL -o /dev/null -w '%{url_effective}' "https://github.com/$FB_REPO/releases/latest" \
        | sed 's#.*/##')

    [ -n "$LATEST_TAG" ] && FB_URL="https://github.com/$FB_REPO/releases/download/$LATEST_TAG/linux-${ARCH_AMD64}-filebrowser.tar.gz"
fi

[ -z "$FB_URL" ] && { 
    echo "❌ 获取版本失败"
    exit 1
}

echo "✅ 成功匹配: $FB_URL"
echo "开始下载并提取二进制..."

if curl -sL --connect-timeout 15 "$FB_URL" \
    | tar -xz -C "$BIN_DIR" filebrowser; then

    chmod +x "$BIN_DIR/filebrowser"

    echo "🎉 完成：已成功提取到 $BIN_DIR/filebrowser"
    ls -lh "$BIN_DIR/filebrowser"
else
    echo "❌ 下载或解压失败"
    exit 1
fi

# 3. 下载并配置 Lucky 二进制文件
LUCKY_BASE="https://release.66666.host"

echo "----------------------------------------------------"
echo "[3/3] 正在解析 Lucky 版本信息..."

# 解析版本号
LUCKY_VER=$(curl -sL "$LUCKY_BASE/" \
    | grep -o 'href="\./v[^/]*' \
    | cut -d/ -f2 \
    | sort -rV \
    | head -1)

[ -z "$LUCKY_VER" ] && { 
    echo "❌ 获取版本失败"
    exit 1
}

# 解析子目录
LUCKY_SUB=$(curl -sL "$LUCKY_BASE/$LUCKY_VER/" \
    | grep -o 'href="\./[^/]*' \
    | cut -d/ -f2 \
    | grep -i '^[0-9].*lucky' \
    | head -1)

[ -z "$LUCKY_SUB" ] && { 
    echo "❌ 未找到 lucky 子目录"
    exit 1
}

# 匹配目标架构安装包
LUCKY_PKG=$(curl -sL "$LUCKY_BASE/$LUCKY_VER/$LUCKY_SUB/" \
    | grep -o 'href="[^"]*' \
    | cut -d'"' -f2 \
    | grep -i "Linux.*$ARCH_X86_64.*\.tar\.gz" \
    | head -1)

[ -z "$LUCKY_PKG" ] && { 
    echo "❌ 未找到 $ARCH_X86_64 包"
    exit 1
}

echo "✅ 成功匹配: $LUCKY_VER / $LUCKY_PKG"
echo "开始下载并提取二进制..."

if curl -sL --connect-timeout 10 "$LUCKY_BASE/$LUCKY_VER/$LUCKY_SUB/$LUCKY_PKG" \
    | tar -xz -C "$BIN_DIR" lucky; then

    chmod +x "$BIN_DIR/lucky"

    echo "🎉 完成：已成功提取到 $BIN_DIR/lucky"
    ls -lh "$BIN_DIR/lucky"
else
    echo "❌ 下载或解压失败"
    exit 1
fi

# 确保默认设置脚本正确收尾
cd "$BUILDER_DIR/openwrt" || exit
sed -i '/exit 0/d' "$ZZZ"
echo "exit 0" >> "$ZZZ"

echo ""
cat "$ZZZ"
echo ""

# ==============================================================================
# 模块 3: 构建配置文件生成 (.config 固件与软件包选择)
# ==============================================================================

cd "$WORKPATH" || exit
touch ./.config

# ------------------------------------------------------------------------------
# 硬件平台与镜像格式 (x86_64)
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_Generic=y
CONFIG_TARGET_ROOTFS_PARTSIZE=2048
CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_IMAGES_PAD=y
CONFIG_QCOW2_IMAGES=y
CONFIG_VHDX_IMAGES=y
CONFIG_VMDK_IMAGES=y
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_IB=y
EOF

# ------------------------------------------------------------------------------
# LuCI 界面与主题插件
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-filebrowser=y
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_luci-app-uhttpd=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-ramfree=y
CONFIG_PACKAGE_luci-app-poweroff=y
EOF

# ------------------------------------------------------------------------------
# 代理、协议与网络扩展
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_ip6tables-mod-nat=y
EOF

# ------------------------------------------------------------------------------
# 文件共享与远程访问
# ------------------------------------------------------------------------------
cat >> .config <<EOF
# --- Samba4 共享 ---
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y
CONFIG_PACKAGE_samba4-libs=y

# 关闭多余共享与 FTP 插件
CONFIG_PACKAGE_autosamba=n
CONFIG_PACKAGE_autosamba_INCLUDE_KSMBD=n
CONFIG_PACKAGE_luci-app-samba=n 
CONFIG_PACKAGE_luci-app-ksmbd=n
CONFIG_PACKAGE_luci-app-minidlna=n
CONFIG_PACKAGE_luci-app-vsftpd=n
CONFIG_PACKAGE_samba36-server=n

# --- SFTP 与 SSH ---
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_openssh-sftp-server=y
EOF

# ------------------------------------------------------------------------------
# 系统工具与硬件监控
# ------------------------------------------------------------------------------
cat >> .config <<EOF
# --- Shell 与基础工具 ---
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_tree=y
CONFIG_PACKAGE_screen=y
CONFIG_PACKAGE_unzip=y

# --- 系统增强与权限 ---
CONFIG_PACKAGE_procps-ng=y
CONFIG_PACKAGE_procps-ng-vmstat=y
CONFIG_PACKAGE_coreutils-stat=y
CONFIG_PACKAGE_shadow-utils=y
CONFIG_PACKAGE_libcap-bin=y

# --- 磁盘与分区管理 ---
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_parted=y
CONFIG_PACKAGE_lsblk=y
CONFIG_PACKAGE_losetup=y
CONFIG_PACKAGE_badblocks=y
CONFIG_PACKAGE_btrfs-progs=y
CONFIG_PACKAGE_ntfsprogs=y
CONFIG_PACKAGE_swap-utils=y

# --- 网络抓包与诊断 ---
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_iw=y

# --- 硬件监控与总线 ---
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_lscpu=y
CONFIG_PACKAGE_sysstat=y
CONFIG_PACKAGE_lm-sensors=y
CONFIG_PACKAGE_irqbalance=y
CONFIG_PACKAGE_usbutils=y
CONFIG_PACKAGE_pciutils=y
EOF

# ------------------------------------------------------------------------------
# 旁路由核心模块 (kmod)
# ------------------------------------------------------------------------------
cat >> .config <<EOF
# --- 防火墙与虚拟网络 ---
CONFIG_PACKAGE_kmod-ipt-core=y
CONFIG_PACKAGE_kmod-ipt-conntrack=y
CONFIG_PACKAGE_kmod-ipt-conntrack-extra=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-ip6tables=y
CONFIG_PACKAGE_kmod-nft-compat=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_kmod-nf-tproxy=y
CONFIG_PACKAGE_kmod-nf-socket=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-macvlan=y
CONFIG_PACKAGE_kmod-br-netfilter=y
CONFIG_PACKAGE_kmod-wireguard=y

# --- 队列与流控加速 ---
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-ifb=y

# --- 有线与虚拟网卡驱动 ---
CONFIG_PACKAGE_kmod-r8125=y
CONFIG_PACKAGE_kmod-r8152=y
CONFIG_PACKAGE_kmod-e1000e=y
CONFIG_PACKAGE_kmod-igb=y
CONFIG_PACKAGE_kmod-i40e=y
CONFIG_PACKAGE_kmod-vmxnet3=y

# --- 存储控制与加密算法 ---
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-squashfs=y
CONFIG_PACKAGE_kmod-ata-ahci=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-crypto-authenc=y
CONFIG_PACKAGE_kmod-crypto-chacha20poly1305=y
CONFIG_PACKAGE_kmod-crypto-curve25519=y

# --- 磁盘格式与挂载支持 ---
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-fs-autofs4=y
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-crypto-crc32c=y
CONFIG_PACKAGE_kmod-lib-crc16=y
CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_cfdisk=y
CONFIG_PACKAGE_parted=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_dosfstools=y
EOF

# ------------------------------------------------------------------------------
# 禁用冗余插件
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-accesscontrol=n
CONFIG_PACKAGE_luci-app-arpbind=n
CONFIG_PACKAGE_luci-app-autoreboot=n
CONFIG_PACKAGE_luci-app-ddns=n
CONFIG_PACKAGE_luci-app-qbittorrent_dynamic=n
CONFIG_PACKAGE_luci-app-rclone_INCLUDE_rclone-webui=n
CONFIG_PACKAGE_luci-app-rclone_INCLUDE_rclone-ng=n
CONFIG_PACKAGE_luci-app-unblockmusic_INCLUDE_UnblockNeteaseMusic_Go=n
CONFIG_PACKAGE_luci-app-vlmcsd=n
CONFIG_PACKAGE_luci-app-vsftpd=n
CONFIG_PACKAGE_luci-app-wol=n
CONFIG_PACKAGE_luci-app-qbittorrent=n
CONFIG_PACKAGE_luci-app-nlbwmon=n
CONFIG_PACKAGE_luci-app-ssr-plus=n
CONFIG_PACKAGE_ddns-scripts_aliyun=n
CONFIG_PACKAGE_ddns-scripts_dnspod=n
CONFIG_PACKAGE_strace=n
EOF

# 移除行首多余缩进与空格
sed -i 's/^[ \t]*//g' ./.config

# 返回工作根目录
cd "$BUILDER_DIR/openwrt" || exit