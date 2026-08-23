#!/bin/sh

# 将默认的shell改为bash
if [ -f /bin/bash ];then
  sed -i '/^root:/s#/bin/ash#/bin/bash#' /etc/passwd
fi

# 添加系统信息
grep "shell-motd" /etc/profile >/dev/null
if [ $? -eq 1 ]; then
echo '
# 添加系统信息
[ -n "$FAILSAFE" -a -x /bin/bash ]  || {
	for FILE in /etc/shell-motd.d/*.sh; do
		[ -f "$FILE" ] && env -i bash "$FILE"
	done
	unset FILE
}

# 设置nano为默认编辑器
export EDITOR="/usr/bin/nano"

' >> /etc/profile
fi

exit 0
