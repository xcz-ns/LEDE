## 替换 OpenWrt 设置文件的方法说明

**注意：以下操作针对已安装好的 OpenWrt 系统（非源码目录）。**

OpenWrt 的所有配置文件均位于 `/etc` 目录。建议使用 **WinSCP** 工具连接设备（文件协议选择 **SCP**）。

### 方法一：手动替换单个文件（适合 1~2 个文件）

1. 在 WinSCP 中找到并打开目标文件（例如 `/etc/config/smartdns`）。
2. 将新的配置内容覆盖粘贴进去。
3. 点击 **保存** 即可。

### 方法二：批量上传 etc 文件夹（适合多文件/多目录）

1. 在电脑本地构建与 OpenWrt 结构一致的文件夹，例如：

   Plaintext

   ```
   etc/
   ├── config/
   │   └── smartdns
   └── smartdns/
       ├── address.conf
       ├── blacklist-ip.conf
       └── custom.conf
   ```

2. 将电脑上的 `etc` 文件夹直接拖拽覆盖上传至路由器的 `/` 根目录下。

### 注意事项

- 修改完成后，需在终端运行 `/etc/init.d/<服务名> restart` 或在 Web 界面重启对应服务使配置生效。
- 请确保上传的文件路径与 OpenWrt 原始目录结构完全一致。