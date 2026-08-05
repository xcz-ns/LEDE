# 修改主机名称为 OpenWrt
uci set system.@system[0].hostname='OpenWrt'

# 设置登录地址192.168.11.103
uci set network.lan.ipaddr='192.168.11.103'
uci commit network
/etc/init.d/network restart

# 给予filebrowser执行权限
chmod +x /usr/bin/filebrowser

# 删除README.md
rm -rf /README.md

exit 0