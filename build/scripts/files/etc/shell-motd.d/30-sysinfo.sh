#!/bin/sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

display()
{
	if [ "$1" = "Battery" ]; then
		local great="<"
	else
		local great=">"
	fi
	if [ -n "$2" ] && [ "$2" != "0" ]; then
		printf "%s:  " "$1"
		if awk "BEGIN{exit ! ($2 $great $3)}"; then
			printf "\e[0;91m%-6s\e[0m" "$2$5"
		else
			printf "\e[0;92m%-6s\e[0m" "$2$5"
		fi
		[ -n "$6" ] && printf "%s" "$6"
		printf "\n"
	fi
}

SHOW_IP_PATTERN="^[ewrv].*|^br.*|^lt.*|^umts.*"

get_ip_addresses()
{
	local ips=""
	for f in /sys/class/net/*; do
		local intf=$(basename "$f")
		if echo "$intf" | grep -qE "$SHOW_IP_PATTERN"; then
			local tmp=$(ip -4 addr show dev "$intf" 2>/dev/null | awk '/inet/ {print $2}' | cut -d'/' -f1)
			[ -n "$tmp" ] && ips="$ips $tmp"
		fi
	done
	echo "$ips" | xargs
}

storage_info()
{
	RootInfo=$(df -h /)
	root_usage=$(awk '/\// {print $(NF-1)}' <<<"${RootInfo}" | sed 's/%//g')
	root_total=$(awk '/\// {print $(NF-4)}' <<<"${RootInfo}")
}

# 修正原脚本中获取 IP 时的后台任务 & 符号可能导致的变量为空问题
ip_address=$(get_ip_addresses)
storage_info
critical_load=$(( 1 + $(grep -c processor /proc/cpuinfo 2>/dev/null || echo 1) / 2 ))

UptimeString=$(uptime | tr -d ',')
time=$(awk -F" " '{print $3" "$4}' <<<"${UptimeString}")
load="$(awk -F"average: " '{print $2}'<<<"${UptimeString}")"
case ${time} in
	1:*)
		time=$(awk -F" " '{print $3" 小时"}' <<<"${UptimeString}")
		;;
	*:*)
		time=$(awk -F" " '{print $3" 小时"}' <<<"${UptimeString}")
		;;
	*days)
		days=$(awk -F" " '{print $3"天"}' <<<"${UptimeString}")
		time=$(awk -F" " '{print $5}' <<<"${UptimeString}")
		time="$days "$(awk -F":" '{print $1"小时 "$2"分钟"}' <<<"${time}")
		;;
esac

mem_info=$(LC_ALL=C free -w 2>/dev/null | grep "^Mem" || LC_ALL=C free | grep "^Mem")
memory_usage=$(awk '{printf("%.0f",(($2-($4+$6))/$2) * 100)}' <<<"${mem_info}")
memory_total=$(awk '{printf("%d",$2/1024)}' <<<"${mem_info}")
swap_info=$(LC_ALL=C free -m | grep "^Swap")
swap_usage=$( (awk '/Swap/ { printf("%3.0f", $3/$2*100) }' <<<"${swap_info}" 2>/dev/null || echo 0) | tr -c -d '[:digit:]')
swap_total=$(awk '{print $(2)}' <<<"${swap_info}")

cpu_temp=$(cpuinfo 2>/dev/null | grep -v '.sh' || echo "N/A")

echo ""
printf "CPU 信息:  \e[0;92m%s\e[0m\n" "$cpu_temp"
display "系统负载" "${load%% *}" "${critical_load}" "0" "" "${load#* }"
printf "运行时间:  \e[0;92m%s\e[0m\n" "$time"
display "内存已用" "$memory_usage" "70" "0" "%" "总空间: ${memory_total} MB"
display "交换内存" "$swap_usage" "10" "0" "%" "总空间: ${swap_total} MB"
display "系统存储" "$root_usage" "90" "1" "%" "总空间: ${root_total}"
printf "IP  地址:  \e[0;92m%s\e[0m\n" "$ip_address"
echo ""

echo -e "------------------------------硬盘使用率---------------------------"
echo "系统空间             类型       总数    已用    可用    使用率  挂载点"
# 去除原生 df 头信息，利用 awk 强制对齐英文字段，避免原生的排版错乱
df -hT / /rom 2>/dev/null | sed '1d' | awk '{printf "%-21s %-10s %-7s %-7s %-7s %-7s %s\n", $1, $2, $3, $4, $5, $6, $7}'
echo ""
