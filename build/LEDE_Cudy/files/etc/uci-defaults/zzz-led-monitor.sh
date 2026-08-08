# 1. 生成核心状态检测脚本
# 逻辑：每次执行时检测物理网卡状态和网络连通性，并相应地设置红白灯的状态。
cat << 'EOF' > /usr/bin/led-monitor.sh
#!/bin/sh
TARGET="223.5.5.5"
WAN_IF="eth0"
RED="/sys/class/leds/red:power"
WHITE="/sys/class/leds/white:status"

set_led() {
    echo none > "$RED/trigger" 2>/dev/null
    echo none > "$WHITE/trigger" 2>/dev/null
    echo 0 > "$RED/brightness" 2>/dev/null
    echo 0 > "$WHITE/brightness" 2>/dev/null
    
    case "$1" in
        white_solid) echo 1 > "$WHITE/brightness" 2>/dev/null ;; 
        red_solid) echo 1 > "$RED/brightness" 2>/dev/null ;;     
        red_blink)                                               
            echo timer > "$RED/trigger" 2>/dev/null
            echo 500 > "$RED/delay_on" 2>/dev/null
            echo 500 > "$RED/delay_off" 2>/dev/null ;;
    esac
}

CARRIER=$(cat /sys/class/net/$WAN_IF/carrier 2>/dev/null)

if [ "$CARRIER" = "0" ] || [ -z "$CARRIER" ]; then
    set_led red_solid
elif ping -q -c 1 -W 1 $TARGET > /dev/null 2>&1; then
    set_led white_solid
else
    set_led red_blink
fi
EOF
chmod +x /usr/bin/led-monitor.sh


# 2. 生成后台守护进程服务
# 逻辑：利用 procd 创建一个常驻后台的服务，每隔2秒循环调用一次上面的检测脚本。
cat << 'EOF' > /etc/init.d/led-daemon
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh -c "while true; do /usr/bin/led-monitor.sh; sleep 2; done"
    procd_set_param respawn
    procd_close_instance
}
EOF
chmod +x /etc/init.d/led-daemon


# 3. 生成网卡热插拔触发器
# 逻辑：监听内核 net 事件，当 eth0 物理状态变化（插拔网线）时，立即重启守护进程，实现零延迟响应。
mkdir -p /etc/hotplug.d/net
cat << 'EOF' > /etc/hotplug.d/net/99-led-trigger
#!/bin/sh
[ "$INTERFACE" = "eth0" ] && /etc/init.d/led-daemon restart
EOF


# 4. 启动服务并设置开机自启
# 逻辑：将写好的守护进程加入开机启动项，并立即运行。
/etc/init.d/led-daemon enable
/etc/init.d/led-daemon restart