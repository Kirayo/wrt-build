# 编译指南

本仓库用于按设备配置自动拉取 OpenWrt / ImmortalWrt / LiBwrt 源码、应用自定义补丁与软件包配置。

## 1. 环境准备

推荐使用 Ubuntu LTS 或其他主流 Linux 发行版。OpenWrt 编译对磁盘空间、内存和文件系统大小写敏感性有要求，建议预留充足磁盘空间并在原生 Linux 文件系统中编译。

## 2. 安装编译依赖

```bash
sudo apt -y update
sudo apt -y full-upgrade
sudo apt install -y dos2unix libfuse-dev
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
```

## 3. 获取源码

```bash
git clone https://github.com/Kirayo/wrt-build.git
cd wrt-build
```

## 4. 编译

### 交互式

直接运行脚本会列出当前 `core/compilecfg/*.ini` 与 `core/deconfig/*.config` 同时存在的设备配置，并提示选择构建模式：

```bash
./build.sh
```

### 直接指定设备 和 模式

```bash
./build.sh <设备配置名> [normal|debug|config_preview]
```

构建模式说明：

| 模式 | 命令示例 | 说明 |
| --- | --- | --- |
| `normal` | `./build.sh zn-m2_libwrt normal` | 拉取源码、应用配置、下载依赖并完整编译固件。 |
| `debug` | `./build.sh xzn-m2_libwrt debug` |  获取编译的最终配置 `config`文件  |
| `config_preview` | `./build.sh zn-m2_libwrt config_preview` | 只预览本项目设置的配置 |

GitHub Actions 的手动构建提供模式选择

## 5. 支持设备

设备配置名来自 `core/compilecfg/` 和 `core/deconfig/` 中同名文件。当前支持：

| 厂商 / 平台 | 设备 | 配置名 |
| --- | --- | --- |
| 兆能 | M2 | `zn-m2_immwrt` |
| 兆能 | M2 - LiBwrt | `zn-m2_libwrt` |

示例：

```bash
./build.sh zn-m2_libwrt
```

## 6. 配置来源

每个设备由两类文件共同定义：

- `core/compilecfg/<设备配置名>.ini`：定义源码仓库、分支、构建目录、默认配置片段、可选提交哈希和容器 SDK 镜像。
- `core/deconfig/<设备配置名>.config`：定义 OpenWrt 目标平台、设备和软件包配置。

不同设备会使用不同上游源码，例如 `VIKINGYFY/immortalwrt`、`immortalwrt/immortalwrt`、`LiBwrt/libwrt`、`padavanonly/immortalwrt-mt798x` 。

构建时会按顺序组合配置：

1. 设备默认 `.config`
2. `compile_base.config`
3. `core/deconfig/fragments/<name>.config` 中的有效配置片段

默认片段由 `compilecfg/*.ini` 的 `CONFIG_FRAGMENTS` 指定：
- 移除 wifi 和 usb 的配置片段 `no-wifi` ，`no-usb`，zn-m2 默认包含
- 配置片段 `nss`，添加 nss 驱动支持。

## 7. 三方插件

三方插件主要通过 feeds 机制加入，使用的第三方源：

```text
https://github.com/kenzok8/openwrt-packages
```


## 8. 项目结构说明

- `build.sh`：编译脚本，支持设备选择、模式选择、配置组合。
- `output/`：完整构建后的固件输出目录，由`build.sh`脚本自动创建。
- `core/scripts/update.sh`：源码更新、feeds 调整、软件包同步和补丁应用主流程。
- `core/compilecfg/`：设备构建元信息 `.ini`。
- `core/deconfig/`：设备和共享默认配置 `.config`。
- `core/deconfig/fragments/`：可组合配置片段。
- `core/modules/`：模块化脚本，包括仓库准备、网络重试、feeds/custom_feed、源码修正、LuCI 修正、服务修正、验证、Docker、CUPS 等静态职责模块。
- `core/patches/`：补丁、默认设置、Wi-Fi 初始化、NSS 诊断、PBR 规则和其他构建时注入文件。

