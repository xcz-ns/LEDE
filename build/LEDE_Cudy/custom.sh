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

git clone --depth 1 https://github.com/xcz-ns/luci-app-wolplus package/luci-app-wolplus
git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/lucky
git clone --depth 1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth 1 https://github.com/vernesong/OpenClash.git package/openclash \
    && mv package/openclash/luci-app-openclash package/ \
    && rm -rf package/openclash package/luci-app-openclash/root/{etc/openclash/GeoSite.dat,usr/share/openclash/ui/{zashboard,metacubexd}}

# 更新、清理并安装 feeds
./scripts/feeds update -a

# 删除冲突软件
rm -rf feeds/luci/applications/{luci-app-openclash,luci-app-ramfree,luci-app-poweroff,luci-app-rclone,luci-app-passwall}
rm -rf feeds/luci/themes/luci-theme-argon

./scripts/feeds install -a -f

# ==============================================================================
# 模块 2: 系统基础配置
# ==============================================================================

# 修改默认时间格式
sed -i 's/localtime[[:space:]]*=[[:space:]]*os.date()/localtime = os.date("%Y年%m月%d日") .. " " .. translate(os.date("%A")) .. " " .. os.date("%X")/g' package/lean/autocore/files/*/index.htm

# 定义配置文件路径
NET="package/base-files/files/bin/config_generate"
ZZZ="package/lean/default-settings/files/zzz-default-settings"

# 增加个性名称
sed -i "s/LEDE /Built on $(TZ=UTC-8 date "+%Y.%m.%d") By XCZNS /g" "$ZZZ"

# 设置主机名、设置 argon 主题
cat >> "$ZZZ" <<EOF
uci set system.@system[0].hostname='CudyTR3000'
uci set luci.main.mediaurlbase=/luci-static/argon
uci commit
EOF

# ------------------------------------------------------------------------------
# 二进制组件预集成 (Lucky)
# ------------------------------------------------------------------------------
BASE="https://release.66666.host"
DIR="$BUILDER_DIR/openwrt/files/usr/bin"
ARCH="arm64"

mkdir -p "$DIR"

echo "----------------------------------------------------"
echo "[1/1] 正在解析 Lucky 版本信息..."

# 解析最新版本号
VER=$(curl -sL "$BASE/" \
    | grep -o 'href="\./v[^/]*' \
    | cut -d/ -f2 \
    | sort -rV \
    | head -1)

[ -z "$VER" ] && { 
    echo "❌ 获取版本失败"
    exit 1
}

# 解析 lucky 子目录
SUB=$(curl -sL "$BASE/$VER/" \
    | grep -o 'href="\./[^/]*' \
    | cut -d/ -f2 \
    | grep -i '^[0-9].*lucky' \
    | head -1)

[ -z "$SUB" ] && { 
    echo "❌ 未找到 lucky 子目录"
    exit 1
}

# 匹配目标架构安装包
PKG=$(curl -sL "$BASE/$VER/$SUB/" \
    | grep -o 'href="[^"]*' \
    | cut -d'"' -f2 \
    | grep -i "Linux.*$ARCH.*\.tar\.gz" \
    | head -1)

[ -z "$PKG" ] && { 
    echo "❌ 未找到 $ARCH 包"
    exit 1
}

echo "✅ 成功匹配: $VER / $PKG"
echo "开始下载并提取二进制..."

if curl -sL --connect-timeout 10 "$BASE/$VER/$SUB/$PKG" \
    | tar -xz -C "$DIR" lucky; then

    chmod +x "$DIR/lucky"

    echo "🎉 完成：已成功提取到 $DIR/lucky"
    ls -lh "$DIR/lucky"
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

# ------------------------------------------------------------------------------
# 硬件平台指定 (MediaTek Filogic / Cudy TR3000)
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-mod=y
CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_IB=y
EOF

# ------------------------------------------------------------------------------
# 基础核心组件配置
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
EOF

# ------------------------------------------------------------------------------
# 预装软件包与扩展插件选择
# ------------------------------------------------------------------------------
cat >> .config <<EOF
# --- Web 界面与美化 ---
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_luci-app-uhttpd=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-ramfree=y
CONFIG_PACKAGE_luci-app-poweroff=y
CONFIG_PACKAGE_luci-app-wolplus=y

# --- 网络代理与虚拟网关 ---
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-proto-wireguard=y

# --- 远程管理与文件传输 ---
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_openssh-sftp-server=y

# --- 系统 Shell 与终端工具 ---
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_tree=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_libcap-bin=y
CONFIG_PACKAGE_screen=y

# --- 系统监控与硬件调试 ---
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_irqbalance=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_tcpdump-mini=y

# --- OpenClash 依赖与防火墙支持 ---
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_ip6tables-mod-nat=y
EOF

cat >> .config <<EOF
# --- USB 3.0 及基础挂载支持 ---
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-fs-autofs4=y
CONFIG_PACKAGE_block-mount=y

# --- EXT4 文件系统及相关驱动支持 ---
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-crypto-crc32c=y
CONFIG_PACKAGE_kmod-lib-crc16=y

# --- 磁盘分区与 EXT4 格式化工具 (e2fsprogs) ---
CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_cfdisk=y
CONFIG_PACKAGE_parted=y

# --- 其他常用 U 盘文件系统支持 (FAT32/exFAT/NTFS) ---
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_dosfstools=y
EOF

# ------------------------------------------------------------------------------
# 禁用冗余插件
# ------------------------------------------------------------------------------
cat >> .config <<EOF
EOF

# 移除行首多余缩进与空格
sed -i 's/^[ \t]*//g' ./.config

# 保留你原有的工作目录跳转逻辑
cd "$BUILDER_DIR/openwrt" || exit