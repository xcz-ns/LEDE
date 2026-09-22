# LEDE 固件自动编译

基于 GitHub Actions + [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 源码的多设备固件自动编译项目。通过云端 CI 一键编译，产物自动发布到 GitHub Releases。

## 支持的设备

| 设备目录 | 设备型号 | 目标平台 |
|---|---|---|
| `LEDE_Cudy` | Cudy TR3000 | mediatek/filogic |
| `LEDE_R3S` | FriendlyElec NanoPi R3S | rockchip/armv8 |
| `LEDE_x86` | x86_64 通用 | x86/64 |

## 目录结构

```
├── .github/workflows/
│   ├── OpenWrt_Build.yml              # 固件编译主工作流
│   ├── Action_Clean.yml               # Release 与运行记录清理（按设备各保留 3 个）
│   ├── OpenWrt_Toolchain_Build.yml   # 工具链编译
│   ├── Export_Caches_to_Artifacts.yml # 编译缓存导出
│   └── Sync Releases to WebDAV.yml    # Release 同步到 WebDAV
├── build/
│   ├── LEDE_Cudy/                     # Cudy 设备配置
│   │   ├── settings.ini               # 编译参数配置
│   │   ├── custom.sh                  # 自定义修改脚本（换源、补丁等）
│   │   ├── .config                    # 固件编译配置（菜单选项）
│   │   └── files/                     # 自定义文件（覆盖到根文件系统）
│   ├── LEDE_R3S/                      # R3S 设备配置
│   ├── LEDE_x86/                      # x86 设备配置
│   └── scripts/
│       └── files/                     # 全局通用自定义文件
└── README.md
```

## 使用方法

### 手动触发编译

1. 进入仓库的 **Actions** 页面
2. 选择 **OpenWrt_Build** 工作流
3. 点击 **Run workflow**
4. 选择要编译的设备（`MODEL`）
5. 可选：开启缓存加速（`CACHE_BUILD`）、SSH 远程配置（`SSH_ACTION`）
6. 等待编译完成，固件自动发布到 **Releases**

### 编译产物

每次编译成功后自动发布 Release，包含：
- 固件镜像（sysupgrade / factory / img 等）
- IPK 插件包
- .config 配置文件
- 可选：SDK、Toolchain

Release tag 格式：`YYYYMMDD-HHMM-设备名`

## 配置说明

每个设备目录下的 `settings.ini` 控制编译行为：

| 参数 | 说明 |
|---|---|
| `REPO_URL` | 源码仓库地址 |
| `REPO_BRANCH` | 源码分支 |
| `CONFIG_FILE` | 编译配置文件名 |
| `FIRMWARE_MESSAGE` | 固件名称（通知与发布用） |
| `CUSTOM_SH` | 自定义脚本文件名 |
| `SSH_ACTIONS` | 是否开启 SSH 远程调试 |
| `UPLOAD_FIRMWARE` | 是否上传固件文件 |
| `UPLOAD_IPK` | 是否上传 IPK 插件包 |
| `UPLOAD_CONFIG` | 是否上传 .config 配置 |
| `UPLOAD_SDK` | 是否上传 SDK |
| `UPLOAD_TOOLCHAIN` | 是否上传 Toolchain |
| `UPLOAD_RELEASE` | 是否发布到 GitHub Releases |
| `TELEGRAM_BOT` | 是否开启 Telegram 通知 |
| `REPO_COMMIT` | 指定源码 commit（空为最新） |

## 清理策略

`Action_Clean.yml` 在每次编译完成后自动触发：
- **Release**：每个设备各自保留最新 **3** 个，更早的自动删除
- **编译运行记录**：每个设备各自保留最新 **3** 条成功记录
- 手动触发时可选择清空全部异常记录（失败/取消/超时）

## 关联项目

- [xcz-ns/LEDE_ImageBuilder](https://github.com/xcz-ns/LEDE_ImageBuilder) — 基于本项目 Release 中的 ImageBuilder 进行二次定制打包
- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) — 固件源码

## 致谢

感谢 [coolsnowwolf](https://github.com/coolsnowwolf) 及所有 LEDE/OpenWrt 贡献者的无私分享！
