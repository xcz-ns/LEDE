#!/bin/bash

# ==============================================================================
# 模块 1: 软件源管理 & 第三方软件包拉取
# ==============================================================================

# 切换 LEDE LuCI 源
sed -i \
  's|^\(src-git luci \).*|\1https://github.com/coolsnowwolf/luci.git;master|' \
  feeds.conf.default
  
sed -i \
  -e '/^#/d' \
  -e '/helloworld/d' \
  feeds.conf.default

# 打印默认 feeds 配置
cat feeds.conf.default

# 下载第三方软件包
git clone --depth 1 https://github.com/kenzok8/small-package small-package
cp -rf small-package/{luci-app-ramfree,luci-app-poweroff} package/

git clone --depth 1 https://github.com/OldCoding/luci-app-filebrowser package/luci-app-filebrowser
git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/lucky
git clone --depth 1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth 1 https://github.com/lisaac/luci-app-dockerman package/luci-app-dockerman
git clone --depth 1 https://github.com/vernesong/OpenClash.git package/openclash \
    && mv package/openclash/luci-app-openclash package/ \
    && rm -rf package/openclash

# 更新、清理并安装 feeds
./scripts/feeds update -a

# 删除冲突软件
rm -rf feeds/luci/applications/{luci-app-openclash,luci-app-filebrowser,luci-app-filebrowser-go,luci-app-dockerman,luci-app-ramfree,luci-app-poweroff,luci-app-rclone}
rm -rf feeds/luci/themes/{luci-theme-argon,luci-theme-design}

./scripts/feeds install -a -f

# ==============================================================================
# 模块 2: 系统基础配置
# ==============================================================================

# 修改内核为 6.12
sed -i 's/KERNEL_PATCHVER:=6.18/KERNEL_PATCHVER:=6.12/' target/linux/rockchip/Makefile

# 修改默认时间格式
sed -i 's/localtime[[:space:]]*=[[:space:]]*os.date()/localtime = os.date("%Y年%m月%d日") .. " " .. translate(os.date("%A")) .. " " .. os.date("%X")/g' package/lean/autocore/files/*/index.htm

# 定义配置文件路径
ZZZ="package/lean/default-settings/files/zzz-default-settings"

# 修改后台地址和网口
cat >> "$ZZZ" << 'EOF'
uci set network.lan.ifname='eth1'
uci set network.lan.ipaddr='192.168.0.1'
uci set network.wan.ifname='eth0'
uci set network.wan6.ifname='eth0'
uci delete network.docker
uci commit network
EOF

# 增加个性名称
sed -i "s/LEDE /Built on $(TZ=UTC-8 date "+%Y.%m.%d") By XCZNS /g" "$ZZZ"

# 设置主机名、设置 argon 主题
cat >> "$ZZZ" <<EOF
uci set system.@system[0].hostname='R3SOS'
uci set luci.main.mediaurlbase=/luci-static/argon
uci commit
EOF

# filebrowser 设置密码
cat >> "$ZZZ" <<EOF
/usr/bin/filebrowser users update admin --database /etc/filebrowser.db --password ZYB18332894508
EOF

# ------------------------------------------------------------------------------
# 二进制组件预集成 (OpenClash / Lucky / Filebrowser)
# ------------------------------------------------------------------------------
CONF="${WORKPATH}/${CUSTOM_SH}"
BIN_DIR="$BUILDER_DIR/openwrt/files/usr/bin"
CORE_DIR="$BUILDER_DIR/openwrt/files/etc/openclash/core"
ARCH="arm64"

mkdir -p "$BIN_DIR" "$CORE_DIR"

# 1. OpenClash Meta 内核预集成
OPENCLASH_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-${ARCH}.tar.gz"

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
FB_ARCH_KEY="linux-${ARCH}-filebrowser.tar.gz"

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

    [ -n "$LATEST_TAG" ] && FB_URL="https://github.com/$FB_REPO/releases/download/$LATEST_TAG/linux-${ARCH}-filebrowser.tar.gz"
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
    | grep -i "Linux.*$ARCH.*\.tar\.gz" \
    | head -1)

[ -z "$LUCKY_PKG" ] && { 
    echo "❌ 未找到 $ARCH 包"
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
# 模块 3: 构建配置文件
# ==============================================================================

cd "$WORKPATH" || exit
touch ./.config

cat <<EOF > .config
# ------------------------------------------------------------------------------
# 目标架构与基础编译选项 (NanoPi R3S - RK3566)
# ------------------------------------------------------------------------------
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r3s=y
CONFIG_TARGET_ROOTFS_PARTSIZE=2048
CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_IB=y

# ------------------------------------------------------------------------------
# 核心网络基础组件
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_iw=y

# ------------------------------------------------------------------------------
# LuCI Web 界面与应用扩展
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_luci-app-uhttpd=y
CONFIG_PACKAGE_luci-app-filebrowser=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_samba4-libs=y
CONFIG_PACKAGE_luci-app-ramfree=y
CONFIG_PACKAGE_luci-app-poweroff=y

# ------------------------------------------------------------------------------
# 系统工具、Shell 与排错诊断
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_tree=y
CONFIG_PACKAGE_screen=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_lscpu=y
CONFIG_PACKAGE_sysstat=y
CONFIG_PACKAGE_lm-sensors=y
CONFIG_PACKAGE_irqbalance=y
CONFIG_PACKAGE_usbutils=y
CONFIG_PACKAGE_pciutils=y
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_openssh-sftp-server=y
CONFIG_PACKAGE_procps-ng=y
CONFIG_PACKAGE_procps-ng-vmstat=y
CONFIG_PACKAGE_coreutils-stat=y
CONFIG_PACKAGE_shadow-utils=y
CONFIG_PACKAGE_libcap-bin=y

# ------------------------------------------------------------------------------
# 磁盘管理与文件系统支持
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_cfdisk=y
CONFIG_PACKAGE_parted=y
CONFIG_PACKAGE_lsblk=y
CONFIG_PACKAGE_losetup=y
CONFIG_PACKAGE_badblocks=y
CONFIG_PACKAGE_swap-utils=y
CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_dosfstools=y
CONFIG_PACKAGE_btrfs-progs=y
CONFIG_PACKAGE_ntfsprogs=y

CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-fs-autofs4=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-squashfs=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-crypto-crc32c=y
CONFIG_PACKAGE_kmod-lib-crc16=y

# ------------------------------------------------------------------------------
# 旁路由与转发防火墙内核驱动 (OpenClash / Docker / 转发加速)
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_ip6tables-mod-nat=y

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
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-ifb=y

# 加密算法与原生/USB网卡
CONFIG_PACKAGE_kmod-crypto-authenc=y
CONFIG_PACKAGE_kmod-crypto-chacha20poly1305=y
CONFIG_PACKAGE_kmod-crypto-curve25519=y
CONFIG_PACKAGE_kmod-r8125=y
CONFIG_PACKAGE_kmod-r8152=y

# ------------------------------------------------------------------------------
# 禁用不需要的冗余插件
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_autosamba=n
CONFIG_PACKAGE_autosamba_INCLUDE_KSMBD=n
CONFIG_PACKAGE_luci-app-samba=n
CONFIG_PACKAGE_luci-app-ksmbd=n
CONFIG_PACKAGE_luci-app-minidlna=n
CONFIG_PACKAGE_luci-app-vsftpd=n
CONFIG_PACKAGE_samba36-server=n

# ------------------------------------------------------------------------------
# 无线驱动核心与 USB 网卡支持 (包含 MT7612U 与 RTL 系列)
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mac80211=y
CONFIG_PACKAGE_kmod-mt76-core=y
CONFIG_PACKAGE_kmod-mt76=y
CONFIG_PACKAGE_kmod-mt76-usb=y
CONFIG_PACKAGE_kmod-mt76x2u=y

# 常见 USB 拓展无线驱动备选 (Realtek & MT7921u)
CONFIG_PACKAGE_kmod-rtl8821cu=y
CONFIG_PACKAGE_kmod-rtl8822cu=y
CONFIG_PACKAGE_kmod-rtw88-usb=y
CONFIG_PACKAGE_kmod-mt7921u=y
CONFIG_PACKAGE_kmod-mt7921-firmware=y

# ------------------------------------------------------------------------------
# 无线管理组件与协议支持 (AP / STA / WPA3)
# ------------------------------------------------------------------------------
CONFIG_PACKAGE_hostapd-common=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_wireless-tools=y
CONFIG_PACKAGE_iw=y
CONFIG_DRIVER_11AC_SUPPORT=y
CONFIG_DRIVER_11AX_SUPPORT=y
CONFIG_WPA_MBO_SUPPORT=y
EOF

# 移除行首多余缩进与空格
sed -i 's/^[ \t]*//g' ./.config

# 保留你原有的工作目录跳转逻辑
cd "$BUILDER_DIR/openwrt" || exit