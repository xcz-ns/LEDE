local i = require "luci.sys"
local t, e
t = Map("wolplus", translate("网络唤醒 +"), translate("Wake on LAN 是一种通过网络远程唤醒局域网内计算机的机制。") .. [[<br/><br/><a href="https://github.com/sundaqiang/openwrt-packages" target="_blank">Powered by sundaqiang</a>]])
t.template = "wolplus/index"
e = t:section(TypedSection, "macclient", translate("客户端设备"))
e.template = "cbi/tblsection"
e.anonymous = true
e.addremove = true
---- 添加设备区块
a = e:option(Value, "name", translate("名称"))
a.optional = false
---- MAC 地址
nolimit_mac = e:option(Value, "macaddr", translate("MAC 地址"))
nolimit_mac.rmempty = false
i.net.mac_hints(function(e, t) nolimit_mac:value(e, "%s (%s)" % {e, t}) end)
----- 网络接口
nolimit_eth = e:option(Value, "maceth", translate("网络接口"))
nolimit_eth.rmempty = false
for t, e in ipairs(i.net.devices()) do if e ~= "lo" then nolimit_eth:value(e) end end
----- 唤醒设备
btn = e:option(Button, "_awake", translate("唤醒主机"))
btn.inputtitle	= translate("唤醒")
btn.inputstyle	= "apply"
btn.disabled	= false
btn.template = "wolplus/awake"
function gen_uuid(format)
    local uuid = i.exec("echo -n $(cat /proc/sys/kernel/random/uuid)")
    if format == nil then
        uuid = string.gsub(uuid, "-", "")
    end
    return uuid
end
function e.create(e, t)
    local uuid = gen_uuid()
    t = uuid
    TypedSection.create(e, t)
end
return t
