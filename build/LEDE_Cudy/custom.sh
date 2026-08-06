#!/bin/bash

# ==============================================================================
# 模块 1: 软件源管理 & 第三方软件包拉取
# ==============================================================================

# 切换 LEDE LuCI 源
sed -i '/luci/d' feeds.conf.default && echo "src-git luci https://github.com/coolsnowwolf/luci.git;master" >> feeds.conf.default

# 打印默认 feeds 配置
cat feeds.conf.default

# 拉取第三方扩展软件包
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky > /dev/null
git clone -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon > /dev/null
git clone --depth 1 https://github.com/vernesong/OpenClash.git package/openclash && mv package/openclash/luci-app-openclash package/ && rm -rf package/openclash

# 更新并安装 feeds
./scripts/feeds update -a > /dev/null
./scripts/feeds install -a -f > /dev/null

# 移除与自定义包冲突的官方包
rm -rf feeds/luci/applications/luci-app-openclash
rm -rf feeds/luci/themes/luci-theme-argon


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

# 网络与防火墙配置 (主路由模式)
cat >> "$ZZZ" <<-EOF
## LAN 基础网络配置
uci set network.lan.delegate='1'                             # 开启内置 IPv6 管理
uci set dhcp.@dnsmasq[0].filter_aaaa='0'                     # 放行 IPv6 DNS 解析

## 防火墙性能与转发优化
uci set firewall.@defaults[0].syn_flood='0'                  # 关闭 SYN 洪水防御
uci set firewall.@defaults[0].flow_offloading='1'            # 开启软件 NAT 加速
uci set firewall.@defaults[0].flow_offloading_hw='1'         # 开启硬件 NAT 加速
uci set firewall.@defaults[0].fullcone='1'                   # 开启 IPv4 FullCone NAT
uci set firewall.@defaults[0].fullcone6='1'                  # 开启 IPv6 FullCone NAT
uci set firewall.@zone[0].masq='1'                           # LAN 区域启用 IP 伪装 NAT
uci set firewall.@zone[0].network='lan ipv6'                 # LAN 绑定 IPv6
uci set firewall.@zone[1].network='wan wan6'                 # WAN 绑定 IPv6

## WAN 口 IPv6 获取模式
uci set network.wan.ipv6='auto'
uci set network.wan.reqaddress='try'
uci set network.wan.reqprefix='auto'

## LAN 口 IPv6 动态分配设置
uci set network.lan.ipv6=1
uci set network.lan.ra_management=1
uci set network.lan.ra_dns=1

## DHCPv6 & 路由通告 (RA) 配置
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ra_flags='managed-config other-config'
uci set dhcp.lan.ra_default='1'
uci set dhcp.lan.dnsv6='2400:da00::6666 2400:da00::6600'

# 应用并提交配置
uci commit dhcp
uci commit network
uci commit firewall
EOF

# OpenClash Meta 内核预集成
if grep -qE '^(CONFIG_PACKAGE_luci-app-openclash=n|# CONFIG_PACKAGE_luci-app-openclash=)' "${WORKPATH}/$CUSTOM_SH"; then
    echo "未启用 OpenClash，添加清理残留配置指令"
    echo 'rm -rf /etc/openclash' >> "$ZZZ"
else
    if grep -q "CONFIG_PACKAGE_luci-app-openclash=y" "${WORKPATH}/$CUSTOM_SH"; then
        arch="arm64" # 硬编码架构为 arm64
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
# 硬件平台指定 (MediaTek Filogic / Cudy TR3000)
# ------------------------------------------------------------------------------
cat >> .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-mod=y
CONFIG_SDK=y
CONFIG_MAKE_TOOLCHAIN=y
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
CONFIG_PACKAGE_luci-theme-argon=y           # Argon 暗黑主题
CONFIG_PACKAGE_luci-app-argon-config=y      # Argon 个性化配置
CONFIG_PACKAGE_luci-app-ttyd=y              # Web SSH 终端
CONFIG_PACKAGE_luci-app-lucky=y             # Lucky 端口转发与反代
CONFIG_PACKAGE_luci-app-diskman=y           # 磁盘管理
CONFIG_PACKAGE_luci-app-wireguard=y

# --- 网络代理与虚拟网关 ---
CONFIG_PACKAGE_luci-app-openclash=y         # OpenClash 分流代理
CONFIG_PACKAGE_luci-proto-wireguard=y       # WireGuard 协议

# --- 远程管理与文件传输 ---
CONFIG_PACKAGE_openssh-client=y             # OpenSSH 客户端
CONFIG_PACKAGE_openssh-sftp-server=y        # SFTP 传输服务

# --- 系统 Shell 与终端工具 ---
CONFIG_PACKAGE_bash=y                       # Bash Shell
CONFIG_PACKAGE_nano=y                       # 文本编辑器
CONFIG_PACKAGE_tree=y                       # 目录树状可视化
CONFIG_PACKAGE_wget-ssl=y                   # HTTP/HTTPS 下载器
CONFIG_PACKAGE_libcap-bin=y                 # 权限管理工具
CONFIG_PACKAGE_screen=y                     # 后台会话管理

# --- 系统监控与硬件调试 ---
CONFIG_PACKAGE_htop=y                       # 交互式资源监视器
CONFIG_PACKAGE_irqbalance=y                 # CPU 中断均衡 (优化 MT7981)
CONFIG_PACKAGE_fdisk=y                      # 磁盘分区管理
CONFIG_PACKAGE_ethtool=y                    # 网卡物理层参数调整
CONFIG_PACKAGE_iw=y                         # 无线网卡控制与诊断
CONFIG_PACKAGE_tcpdump-mini=y               # 轻量级网络抓包

# --- OpenClash 依赖与防火墙支持 ---
CONFIG_PACKAGE_ipset=y                      # IPSet 集合匹配
CONFIG_PACKAGE_iptables-mod-tproxy=y        # TProxy 透明代理
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y # 连接跟踪扩展
CONFIG_PACKAGE_iptables-mod-extra=y         # iptables 增强规则
CONFIG_PACKAGE_kmod-ipt-nat6=y              # IPv6 NAT 内核扩展
CONFIG_PACKAGE_ip6tables-mod-nat=y          # IPv6 防火墙 NAT 规则
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
CONFIG_PACKAGE_luci-app-qbittorrent=n
CONFIG_PACKAGE_luci-app-vlmcsd=n
CONFIG_PACKAGE_luci-app-vsftpd=n
CONFIG_PACKAGE_luci-app-wol=n
CONFIG_PACKAGE_luci-app-nlbwmon=n
EOF

# 启用fw4，禁用fw3
cat >> .config <<EOF
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_nftables=y
CONFIG_PACKAGE_kmod-nft-core=y
CONFIG_PACKAGE_kmod-nft-nat=y
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_firewall
CONFIG_PACKAGE_iptables
CONFIG_PACKAGE_ip6tables
EOF

# ------------------------------------------------------------------------------
# 格式清理与收尾
# ------------------------------------------------------------------------------
# 移除行首多余缩进与空格
sed -i 's/^[ \t]*//g' ./.config

# 返回工作根目录
cd "$HOME" || exit

# 脚本逻辑结束