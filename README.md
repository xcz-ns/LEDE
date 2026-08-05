# LEDE 自定义固件编译系统

基于 GitHub Actions 的 OpenWrt/LEDE 自动化编译项目，支持 **x86_64 虚拟机平台**和 **Cudy TR3000 旅行路由器**两种目标固件的云端一键编译、自动发布与通知。

## 功能特性

- **多平台支持**：x86_64（旁路由模式）与 MediaTek Filogic / Cudy TR3000（主路由模式）
- **云端全自动编译**：基于 GitHub Actions，无需本地环境，Fork 后即可触发构建
- **缓存加速**：集成 `cachewrtbuild`，利用 ccache 缓存大幅缩短重复编译时间
- **SSH 远程调试**：可选启用 SSH 连接到构建环境，方便交互式排错
- **多格式镜像输出**：x86 平台自动生成 QCOW2（PVE/KVM）、VHDX（Hyper-V）、VMDK（VMware）等虚拟机镜像
- **自动发布与通知**：编译完成后自动创建 GitHub Release，并推送 Telegram 消息通知
- **自动清理**：构建完成后自动清理旧版 Release（保留最近 10 个）和工作流记录，节省仓库空间
- **预集成第三方插件**：OpenClash（Meta 内核预下载）、Argon 主题、Docker 管理、FileBrowser、Lucky、WireGuard 等
- **深度网络优化**：IPv6 FullCone NAT、硬件 NAT 加速、TProxy 透明代理、Cake 队列流控等

## 环境要求

| 项目 | 要求 |
|------|------|
| 代码托管 | GitHub 账号（需 Fork 本仓库） |
| 构建环境 | GitHub Actions `ubuntu-22.04` Runner（自动分配） |
| 磁盘空间 | 约 50GB+（工作流会自动创建 LVM 编译盘扩充空间） |
| Secrets（可选） | `MY_GITHUB_TOKEN`、`TELEGRAM_BOT_TOKEN`、`TELEGRAM_CHAT_ID` |

> 无需本地安装任何编译工具链，全部在云端完成。

## 安装步骤

1. **Fork 仓库**
   ```bash
   # 在浏览器中访问本仓库，点击右上角 Fork 按钮
   ```

2. **配置 Secrets**（可选，用于自动发布和通知）

   进入 Fork 后的仓库 → `Settings` → `Secrets and variables` → `Actions` → `New repository secret`，添加：

   | Secret 名称 | 用途 |
   |-------------|------|
   | `MY_GITHUB_TOKEN` | 发布 Release 所需的 GitHub Token |
   | `TELEGRAM_BOT_TOKEN` | Telegram 机器人通知 Token |
   | `TELEGRAM_CHAT_ID` | Telegram 接收消息的 Chat ID |

3. **触发编译**

   进入仓库 → `Actions` → 选择 `OpenWrt_LEDE Build` 工作流 → `Run workflow`，选择目标固件后点击运行。

## 使用方法

### 触发编译

在 GitHub Actions 页面手动触发工作流时，可选择以下参数：

| 参数 | 说明 | 可选值 |
|------|------|--------|
| `MODEL` | 编译的固件目标 | `LEDE_Cudy` / `LEDE_x86` |
| `CACHE_BUILD` | 缓存加速 | `true` / `false` |
| `SSH_ACTION` | SSH 远程调试 | `true` / `false` |

### 获取固件

编译完成后，固件产物通过以下方式分发：

- **GitHub Release**：自动发布到 [Releases 页面](https://github.com/xcz-ns/LEDE/releases)
- **Artifacts**：在 Actions 运行页面下载，包含固件、IPK 插件包、SDK、Toolchain、配置文件等

### 固件默认配置

| 属性 | LEDE_x86 | LEDE_Cudy |
|------|----------|-----------|
| 运行模式 | 旁路由 | 主路由 |
| 默认 IP | `192.168.11.103` | DHCP 获取 |
| 管理后台 | LuCI（Argon 主题） | LuCI（Argon 主题） |
| 内核版本 | 6.6 | 跟随源码 |
| WiFi | 无 | 2.4G + 5G 双频 |
| 虚拟机镜像 | QCOW2 / VHDX / VMDK | 无 |
| 预装核心组件 | OpenClash、Docker、FileBrowser、Samba4、WireGuard | OpenClash、WireGuard、Lucky |

## 项目结构

```
LEDE/
├── .github/
│   └── workflows/
│       ├── OpenWrt_LEDE_Build.yml   # 核心编译工作流
│       └── Cleanup.yml              # 自动清理工作流
├── build/
│   ├── LEDE_x86/                    # x86_64 固件构建配置
│   │   ├── settings.ini             # 编译参数配置
│   │   ├── custom.sh                # 自定义构建脚本（源、插件、.config）
│   │   ├── files/                   # 预置配置文件（覆盖到 /etc）
│   │   │   └── etc/
│   │   │       ├── config/          # UCI 配置（network, firewall, openclash 等）
│   │   │       ├── uci-defaults/    # 首次启动初始化脚本
│   │   │       └── usr/bin/         # 预装二进制（filebrowser）
│   │   └── sources/                 # 源码级替换文件（编译时生效）
│   │
│   ├── LEDE_Cudy/                   # Cudy TR3000 固件构建配置
│   │   ├── settings.ini
│   │   ├── custom.sh
│   │   ├── files/
│   │   │   └── etc/
│   │   │       ├── config/          # wireless, openclash, turboacc 等
│   │   │       └── uci-defaults/
│   │   └── sources/
│   │
│   └── scripts/                     # 通用脚本与文件
│       └── files/
│           └── etc/
│               ├── shell-motd.d/    # SSH 登录信息脚本
│               └── uci-defaults/    # 通用初始化脚本
├── .gitattributes
└── README.md
```

## 配置说明

### settings.ini

每个目标固件目录下的 `settings.ini` 是编译入口配置，定义了源码、上传行为和通知开关：

```ini
REPO_URL="https://github.com/coolsnowwolf/lede"   # LEDE 源码地址
REPO_BRANCH="master"                               # 源码分支
CONFIG_FILE=".config"                              # 编译配置文件名
FIRMWARE_MESSAGE="LEDE_x86"                        # 固件标识（用于发布和通知）
CUSTOM_SH="custom.sh"                              # 自定义构建脚本
CACHE_BUILD="false"                                # 缓存加速开关
SSH_ACTIONS="false"                                # SSH 调试开关
UPLOAD_FIRMWARE="true"                             # 上传固件
UPLOAD_QCOW2="true"                                # 上传 PVE/KVM 镜像
UPLOAD_VHDX="true"                                 # 上传 Hyper-V 镜像
UPLOAD_VMDK="true"                                 # 上传 VMware 镜像
UPLOAD_IPK="true"                                  # 上传 IPK 插件包
UPLOAD_CONFIG="true"                               # 上传 .config 配置
UPLOAD_RELEASE="true"                              # 发布到 GitHub Release
UPLOAD_SDK="true"                                  # 上传 SDK
UPLOAD_TOOLCHAIN="true"                            # 上传 Toolchain
TELEGRAM_BOT="true"                                # Telegram 通知
REPO_COMMIT=""                                     # 指定 commit（留空则用分支最新）
```

### custom.sh

构建脚本分为三大模块：

1. **软件源管理**：切换 LuCI 源，拉取第三方插件包（OpenClash、Argon 主题、Docker 管理等），更新 feeds
2. **系统配置**：修改主机名、默认主题、时间格式、内核版本锁定、预下载 OpenClash Meta 内核、UCI 网络与防火墙优化
3. **配置生成**：动态生成 `.config` 文件，定义目标平台、LuCI 插件、kmod 内核模块、系统工具等

### files/ 目录

`files/` 中的文件会按目录结构覆盖到固件根文件系统（`/etc` 下）。例如 `files/etc/config/network` 会成为路由器的网络配置。

### sources/ 目录

`sources/` 中的文件会覆盖到 OpenWrt **源码目录**，影响编译过程本身（如替换 `package/base-files/files/etc/banner`）。

## 依赖列表

### 第三方软件包源

| 包名 | 来源 | 用途 |
|------|------|------|
| luci (coolsnowwolf) | `github.com/coolsnowwolf/luci` | LEDE 定制 LuCI 界面 |
| luci-app-filebrowser | `github.com/OldCoding/luci-app-filebrowser` | Web 文件管理器（仅 x86） |
| luci-lib-docker | `github.com/lisaac/luci-lib-docker` | Docker LuCI 库（仅 x86） |
| luci-app-dockerman | `github.com/lisaac/luci-app-dockerman` | Docker 容器管理（仅 x86） |
| luci-app-lucky | `github.com/gdy666/luci-app-lucky` | 端口转发与反向代理 |
| luci-theme-argon | `github.com/jerrykuku/luci-theme-argon` | Argon 暗色主题 |
| OpenClash | `github.com/vernesong/OpenClash` | Clash 代理分流 |

### GitHub Actions

| Action | 用途 |
|--------|------|
| `actions/checkout@v6` | 拉取仓库代码 |
| `jlumbroso/free-disk-space@main` | 释放 Runner 磁盘空间 |
| `xcz-ns/cachewrtbuild@main` | 编译缓存加速 |
| `db-one/debugger-action@main` | SSH 远程调试 |
| `actions/upload-artifact@node24` | 上传构建产物 |
| `ncipollo/release-action@v1` | 发布 GitHub Release |
| `xcz-ns/delete-older-releases@main` | 清理旧版 Release |
| `Mattraks/delete-workflow-runs@v2` | 清理工作流记录 |

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进本项目。贡献时请注意：

1. **Fork 仓库**并创建特性分支：`git checkout -b feature/your-feature`
2. **修改配置**时请确保 `settings.ini`、`custom.sh` 和 `files/` 三者的对应关系正确
3. **测试验证**：提交前建议先在自己的 Fork 中触发一次编译，确认工作流正常
4. **提交规范**：Commit message 使用简洁明了的描述，如 `feat: 添加 XXX 插件支持` 或 `fix: 修复 XXX 配置问题`
5. **Pull Request**：请描述清楚修改内容、修改原因及测试结果

## 开源许可证

本项目仅包含编译配置与自定义脚本，不包含 OpenWrt/LEDE 源码。

- **本仓库的配置文件与脚本**：基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 项目修改，遵循其原始许可证
- **OpenWrt 源码**：遵循 [GPL-2.0-or-later](https://openwrt.org/about) 许可证
- **第三方插件**：分别遵循各自的许可证

> 使用本项目编译出的固件仅供学习和个人使用，请遵守相关法律法规。
