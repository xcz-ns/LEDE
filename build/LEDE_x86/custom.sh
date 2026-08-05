#!/bin/bash

# ==============================================================================
# 模块 1: 软件源管理 & 第三方软件包拉取
# ==============================================================================

# 切换 LEDE LuCI 源
sed -i '/luci/d' feeds.conf.default && echo "src-git luci https://github.com/coolsnowwolf/luci.git;master" >> feeds.conf.default

# 打印默认 feeds 配置
cat feeds.conf.default

# 拉取第三方扩展软件包
git clone https://github.com/OldCoding/luci-app-filebrowser package/luci-app-filebrowser
git clone https://github.com/lisaac/luci-lib-docker.git package/luci-lib-docker > /dev/null
git clone https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman > /dev/null
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky > /dev/null
git clone -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon > /dev/null
git clone --depth 1 https://github.com/vernesong/OpenClash.git package/openclash && mv package/openclash/luci-app-openclash package/ && rm -rf package/openclash

# 更新并安装 feeds
./scripts/feeds update -a > /dev/null
./scripts/feeds install -a -f > /dev/null

# 移除与自定义包冲突的官方包
rm -rf feeds/luci/applications/luci-app-openclash
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf package/feeds/luci/luci-app-passwall
rm -rf lede/feeds/luci/applications/luci-app-filebrowser/
rm -rf feeds/luci/applications/luci-app-filebrowser-go/


# ==============================================================================
# 模块 2: 系统基础配置 & 网络初始化 (UCI 定制)
# ==============================================================================

# 定义配置文件路径
NET="package/base-files/files/bin/config_generate"
ZZZ="package/lean/default-settings/files/zzz-default-settings"

# 基础系统设置
sed -i "s/LEDE /Built on $(TZ=UTC-8 date "+%Y.%m.%d") By XCZNS /g" "$ZZZ" # 增加自己个性名称
echo "uci set luci.main.mediaurlbase=/luci-static/argon" >> "$ZZZ"                 # 默认主题设为 Argon
sed -i 's#localtime  = os.date()#localtime  = os.date("%Y年%m月%d日") .. " " .. translate(os.date("%A")) .. " " .. os.date("%X")#g' package/lean/autocore/files/*/index.htm # 修改默认时间格式

# 锁定内核版本为 6.6
sed -i 's/^KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.6/g' target/linux/x86/Makefile
sed -i 's/^KERNEL_TESTING_PATCHVER:=.*/KERNEL_TESTING_PATCHVER:=6.6/g' target/linux/x86/Makefile
echo "内核版本已成功强制修改为 6.6"

# OpenClash Meta 内核预集成
if grep -qE '^(CONFIG_PACKAGE_luci-app-openclash=n|# CONFIG_PACKAGE_luci-app-openclash=)' "${WORKPATH}/$CUSTOM_SH"; then
    echo "未启用 OpenClash，添加清理残留配置指令"
    echo 'rm -rf /etc/openclash' >> "$ZZZ"
else
    if grep -q "CONFIG_PACKAGE_luci-app-openclash=y" "${WORKPATH}/$CUSTOM_SH"; then
        arch="amd64" # 硬编码架构
        echo "下载 OpenClash Meta 核心 [$arch]..."
        
        mkdir -p "$HOME/clash-core"
        mkdir -p "$HOME/files/etc/openclash/core"
        cd "$HOME/clash-core" || exit 1

        # 下载 Core 包 (重试 3 次, 15 秒超时)
        if wget -q --tries=3 --timeout=15 "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-$arch.tar.gz"; then
            echo "下载成功，开始部署..."
        else
            echo "错误：内核下载失败，请检查网络！"
            exit 1
        fi

        tar -zxvf "clash-linux-$arch.tar.gz"
        if [[ -f "$HOME/clash-core/clash" ]]; then
            mv -f "$HOME/clash-core/clash" "$HOME/files/etc/openclash/core/clash_meta"
            chmod +x "$HOME/files/etc/openclash/core/clash_meta"
            echo "OpenClash Meta 内核集成成功"
        else
            echo "内核解压/部署失败"
            exit 1
        fi

        # 清理临时文件
        cd "$HOME" || exit
        rm -rf "$HOME/clash-core"
    fi
fi

# 确保默认设置脚本正确收尾
cd "$HOME" || exit
sed -i '/exit 0/d' "$ZZZ"
echo "exit 0" >> "$ZZZ"

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
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_IMAGES_PAD=y
CONFIG_QCOW2_IMAGES=y
CONFIG_VHDX_IMAGES=y
CONFIG_VMDK_IMAGES=y
CONFIG_SDK=y
CONFIG_MAKE_TOOLCHAIN=y
EOF

# ------------------------------------------------------------------------------
# LuCI 界面与主题插件
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_PACKAGE_luci-theme-argon=y            # Argon 主题
CONFIG_PACKAGE_luci-app-argon-config=y       # Argon 个性化配置
CONFIG_PACKAGE_luci-app-ttyd=y               # Web SSH 终端
CONFIG_PACKAGE_luci-app-lucky=y              # Lucky 转发与反代
CONFIG_PACKAGE_luci-app-diskman=y            # 磁盘管理
CONFIG_PACKAGE_luci-app-dockerman=y          # Docker 容器管理
CONFIG_PACKAGE_luci-app-filebrowser=y
CONFIG_PACKAGE_luci-app-wireguard=y

EOF

# ------------------------------------------------------------------------------
# 代理、协议与网络扩展
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y         # Dnsmasq (完整版带 DHCPv6)
CONFIG_PACKAGE_luci-app-openclash=y          # OpenClash 分流
CONFIG_PACKAGE_luci-proto-wireguard=y        # WireGuard 协议
CONFIG_PACKAGE_ipset=y                       # IPSet 匹配
CONFIG_PACKAGE_iptables-mod-tproxy=y         # TProxy 透明代理
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_ip6tables-mod-nat=y           # IPv6 防火墙 NAT
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
CONFIG_PACKAGE_strace=n
EOF

# ------------------------------------------------------------------------------
# 格式清理与收尾
# ------------------------------------------------------------------------------
# 移除行首多余缩进与空格
sed -i 's/^[ \t]*//g' ./.config

# 返回工作根目录
cd "$HOME" || exit

# 脚本逻辑结束