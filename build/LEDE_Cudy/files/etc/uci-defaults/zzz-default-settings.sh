# 修改主机名称为 OpenWrt
uci set system.@system[0].hostname='OpenWrt'

# 设置登录地址192.168.10.1
uci set network.lan.ipaddr='192.168.10.1'
uci commit network
/etc/init.d/network restart

# 删除README.md
rm -rf /README.md

exit 0