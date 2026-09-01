#!/bin/bash

# ==============================================================================
# 模块 1: 软件源管理 & 第三方软件包拉取
# ==============================================================================

# 切换 LEDE LuCI 源
sed -i 's/^\(src-git luci \).*/\1https:\/\/github.com\/coolsnowwolf\/luci.git;master/' feeds.conf.default
sed -i '/^#/d' feeds.conf.default

# 打印默认 feeds 配置
cat feeds.conf.default

# 下载第三方软件包
git clone --depth 1 https://github.com/OldCoding/luci-app-filebrowser package/luci-app-filebrowser
git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/lucky
git clone --depth 1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth 1 https://github.com/lisaac/luci-app-dockerman package/luci-app-dockerman
git clone --depth 1 https://github.com/vernesong/OpenClash.git package/openclash && mv package/openclash/luci-app-openclash package/ && rm -rf package/openclash

# 更新、清理并安装 feeds
./scripts/feeds update -a

# 删除冲突软件
rm -rf feeds/luci/applications/{luci-app-openclash,luci-app-filebrowser,luci-app-filebrowser-go,luci-app-dockerman}
rm -rf feeds/luci/themes/{luci-theme-argon,luci-theme-design}

./scripts/feeds install -a -f

sed -i 's/\$(call opkg,\$(TARGET_DIR)) install/\$(call opkg,\$(TARGET_DIR)) install --force-overwrite/g' package/Makefile

# ==============================================================================
# 模块 2: 系统基础配置
# ==============================================================================

# 修改默认时间格式
sed -i 's/localtime[[:space:]]*=[[:space:]]*os.date()/localtime = os.date("%Y年%m月%d日") .. " " .. translate(os.date("%A")) .. " " .. os.date("%X")/g' package/lean/autocore/files/*/index.htm

# 定义配置文件路径
NET="package/base-files/files/bin/config_generate"
ZZZ="package/lean/default-settings/files/zzz-default-settings"

# 修改后台地址
sed -i 's#192.168.1.1#192.168.0.1#g' "$NET"

# 增加个性名称
sed -i "s/LEDE /Built on $(TZ=UTC-8 date "+%Y.%m.%d") By XCZNS /g" "$ZZZ"

# 设置主机名、设置argon主题
cat >> "$ZZZ" <<EOF
uci set system.@system[0].hostname='R3SOS'
uci set luci.main.mediaurlbase=/luci-static/argon
uci commit
EOF

# filebrowser 设置密码
cat >> "$ZZZ" <<EOF
/usr/bin/filebrowser users update admin --database /etc/filebrowser.db --password ZYB18332894508
EOF

# OpenClash Meta 内核预集成
CONF="${WORKPATH}/${CUSTOM_SH}"
CORE_DIR="${BUILDER_DIR}/openwrt/files/etc/openclash/core"
URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"

if grep -q "^CONFIG_PACKAGE_luci-app-openclash=y" "$CONF"; then
    echo "开始下载并部署 OpenClash Meta 核心..."
    mkdir -p "$CORE_DIR"
    if wget -qO- --tries=3 --timeout=15 "$URL" | tar xz -C "$CORE_DIR"; then
        mv -f "$CORE_DIR/clash" "$CORE_DIR/clash_meta"
        chmod +x "$CORE_DIR/clash_meta"
        echo "✅ OpenClash Meta 内核集成成功,文件信息如下："
        ls -lh "$CORE_DIR/clash_meta"
    else
        echo "❌ 错误：内核下载或解压失败！"
        exit 1
    fi
else
    echo "未启用 OpenClash,添加清理残留配置指令..."
    echo 'rm -rf /etc/openclash' >> "$ZZZ"
fi

# 下载并配置 filebrowser 二进制文件
REPO="filebrowser/filebrowser"
DIR="$BUILDER_DIR/openwrt/files/usr/bin"
ARCH_KEY="linux-arm64-filebrowser.tar.gz"

mkdir -p "$DIR"
echo "[1/2] 正在获取 GitHub 最新 Release 信息..."
DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o "https://[^\"]*${ARCH_KEY}" \
  | head -n 1)
if [ -z "$DOWNLOAD_URL" ]; then
  LATEST_TAG=$(curl -sIL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" | sed 's#.*/##')
  [ -n "$LATEST_TAG" ] && DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_TAG/linux-arm64-filebrowser.tar.gz"
fi
[ -z "$DOWNLOAD_URL" ] && { echo "❌ 获取下载链接失败"; exit 1; }
echo "✅ 匹配到下载地址: $DOWNLOAD_URL"
echo "[2/2] 开始下载并提取二进制..."
curl -sL --connect-timeout 15 "$DOWNLOAD_URL" | tar -xz -C "$DIR" filebrowser || { echo "❌ 下载或解压失败"; exit 1; }
chmod +x "$DIR/filebrowser"
echo "🎉 完成：已成功提取到 $DIR/filebrowser"
ls -lh "$DIR/filebrowser"


# 下载并配置 lucky 二进制文件
BASE="https://release.66666.host"
DIR="$BUILDER_DIR/openwrt/files/usr/bin"
ARCH="arm64"

mkdir -p "$DIR"
echo "[1/2] 正在解析最新版本信息..."
VER=$(curl -sL "$BASE/" | grep -o 'href="\./v[^/]*' | cut -d/ -f2 | sort -rV | head -1)
[ -z "$VER" ] && { echo "❌ 获取版本失败"; exit 1; }
SUB=$(curl -sL "$BASE/$VER/" | grep -o 'href="\./[^/]*' | cut -d/ -f2 | grep -i '^[0-9].*lucky' | head -1)
[ -z "$SUB" ] && { echo "❌ 未找到 lucky 子目录"; exit 1; }
PKG=$(curl -sL "$BASE/$VER/$SUB/" | grep -o 'href="[^"]*' | cut -d'"' -f2 | grep -i "Linux.*$ARCH.*\.tar\.gz" | head -1)
[ -z "$PKG" ] && { echo "❌ 未找到 $ARCH 包"; exit 1; }
echo "✅ 成功匹配: $VER / $PKG"
echo "[2/2] 开始下载并提取二进制..."
curl -sL --connect-timeout 10 "$BASE/$VER/$SUB/$PKG" | tar -xz -C "$DIR" lucky || { echo "❌ 下载或解压失败"; exit 1; }
echo "🎉 完成：已成功提取到 $DIR/lucky"
ls -lh "$DIR/lucky"

# 确保默认设置脚本正确收尾
cd "$BUILDER_DIR/openwrt" || exit
sed -i '/exit 0/d' "$ZZZ"
echo "exit 0" >> "$ZZZ"

echo ""
cat "$NET"
echo ""

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
CONFIG_SDK=y
CONFIG_MAKE_TOOLCHAIN=y
CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_DEVEL=y
CONFIG_CCACHE=y

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
CONFIG_PACKAGE_docker-compose=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_samba4-libs=y

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
CONFIG_PACKAGE_luci-app-accesscontrol=n
CONFIG_PACKAGE_luci-app-arpbind=n
CONFIG_PACKAGE_luci-app-autoreboot=n
CONFIG_PACKAGE_luci-app-ddns=n
CONFIG_PACKAGE_luci-app-qbittorrent_dynamic=n
CONFIG_PACKAGE_luci-app-qbittorrent=n
CONFIG_PACKAGE_luci-app-vlmcsd=n
CONFIG_PACKAGE_luci-app-wol=n
CONFIG_PACKAGE_luci-app-nlbwmon=n
CONFIG_PACKAGE_luci-app-ssr-plus=n
CONFIG_PACKAGE_luci-app-upnp=n
CONFIG_PACKAGE_ddns-scripts_aliyun=n
CONFIG_PACKAGE_ddns-scripts_dnspod=n

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