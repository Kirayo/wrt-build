# wrt-build 编译说明

本仓库用于按设备维度自动拉取上游 OpenWrt / ImmortalWrt / LiBwrt 源码，按配置组合最终 `.config`，并应用自定义补丁、Feeds 与软件包修正，以便批量生成目标路由器固件。

它的核心思路是：

- 设备配置独立：每个设备对应一个 `*.ini` + `*.config`
- 构建流程统一：通过 `build.sh` 选择设备和构建模式
- 配置组合可控：基础配置 + 片段配置 + 设备主配置
- 自动化补丁：统一处理源码修正、feeds 修改、系统默认设置

---

## 1. 环境准备

建议在 Ubuntu LTS / Debian 系列 Linux 环境下编译。OpenWrt 编译要求较高的磁盘空间与内存，建议至少保留较充足空间，并尽量在原生 Linux 文件系统中进行编译，而不是 Windows 上的挂载目录。

### 安装编译依赖

```bash
sudo apt -y update
sudo apt -y full-upgrade
sudo apt install -y dos2unix libfuse-dev
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
```

如果你已经有较完整的 OpenWrt 编译环境，也可以跳过这一步，直接进入源码构建流程。

---

## 2. 获取源码

```bash
git clone https://github.com/Kirayo/wrt-build.git
cd wrt-build
```

仓库根目录中已经包含编译脚本、设备配置和模块脚本，通常不需要额外初始化步骤。

---

## 3. 构建方式

### 3.1 交互式选择

直接执行脚本时，程序会扫描 `core/compilecfg/*.ini` 和 `core/deconfig/*.config`，列出所有支持的设备，并让你在终端中选择设备与构建模式：

```bash
./build.sh
```

### 3.2 直接指定设备和模式

```bash
./build.sh <device> [normal|debug|config_preview]
```

可用模式：

| 模式 | 示例 | 说明 |
| --- | --- | --- |
| `normal` | `./build.sh zn-m2_libwrt normal` | 拉取源码、合并配置、下载依赖并完整编译固件 |
| `debug` | `./build.sh xiaomi-ax3000t debug` | 生成最终 `.config` 和 `diffconfig`，用于排查配置问题 |
| `config_preview` | `./build.sh zn-m2_libwrt config_preview` | 仅预览当前设备会合并哪些配置和片段 |

> 说明：脚本在无参数状态下会进入交互式菜单；若带参数则会直接按指定设备和模式执行。

---

## 4. 当前支持的设备

本项目支持的设备名由 `core/compilecfg/` 和 `core/deconfig/` 中同名文件决定。当前已覆盖的设备包括：

| 厂商 / 平台 | 设备 | 配置名 |
| --- | --- | --- |
| 小米 | Mi Router AX3000T | `xiaomi-ax3000t` |
| 兆能 | M2 | `zn-m2_immwrt` |
| 兆能 | M2 - LiBwrt | `zn-m2_libwrt` |

例如：

```bash
./build.sh xiaomi-ax3000t normal
./build.sh zn-m2_libwrt debug
```

---

## 5. 配置文件结构

每个设备都有两类核心配置：

- `core/compilecfg/<device>.ini`
  - 定义源码仓库地址 `REPO_URL`
  - 定义分支 `REPO_BRANCH`
  - 定义构建目录 `BUILD_DIR`
  - 定义启用的配置片段 `CONFIG_FRAGMENTS`
  - 可选提交锁定 `COMMIT_HASH`

- `core/deconfig/<device>.config`
  - 定义目标平台、设备名、软件包选择、驱动和 LuCI 配置

示例：

```ini
REPO_URL=https://github.com/LiBwrt/LibWrt.git
REPO_BRANCH=25.12-nss
BUILD_DIR=libwrt
CONFIG_FRAGMENTS=nss,no-wifi,no-usb
```

---

## 6. 配置合并顺序

构建时会按以下顺序组装最终 `.config`：

1. `core/deconfig/base.config`
2. `core/deconfig/fragments/*.config` 中按 `CONFIG_FRAGMENTS` 指定的片段
3. `core/deconfig/<device>.config`

最终配置中的设备级 `.config` 会覆盖前面相同项，确保目标设备配置优先级最高。

### 常见片段说明

`CONFIG_FRAGMENTS` 可组合多个配置片段，例如：

- `no-wifi`：关闭 WiFi 相关配置
- `no-usb`：关闭 USB 相关配置
- `nss`：启用 NSS 相关支持

你可以在 `core/deconfig/fragments/` 中查看实际片段文件内容，按需要扩展。

---

## 7. 构建流程说明

`build.sh` 主要执行以下步骤：

1. 识别并校验设备是否存在
2. 解析 `*.ini` 的构建参数
3. 读取 `CONFIG_FRAGMENTS`
4. 组合主配置
5. 执行 `make defconfig`
6. 根据模式执行：
   - `normal`：完整编译并输出固件
   - `debug`：输出 `diffconfig` 与最终 `.config`
   - `config_preview`：仅打印配置合并顺序与片段信息

在编译前，还会对源码执行一些补丁与修正，例如：

- feeds 和源替换
- 修复 default-settings
- 禁用不需要的自动挂载
- 处理 x86_64 distfeeds 等特殊项

---

## 8. 输出目录

编译完成后，固件会输出到：

```text
output/
```

脚本会根据目标目录中生成的镜像文件自动复制并整理到 `output/`，便于直接查看或烧录。

在 `debug` 模式下，额外输出：

```text
output/debug/
```

其中保存：

- `<device>.config`：编译后的最终配置
- `<device>.diffconfig`：配置差异

---

## 9. 项目结构说明

```text
wrt-build/
├── build.sh                  # 主入口脚本
├── README.md                 # 说明文档
├── core/
│   ├── compilecfg/            # 设备构建信息 .ini
│   ├── deconfig/              # 设备配置 .config 与公共基础配置
│   │   ├── base.config
│   │   └── fragments/
│   ├── modules/               # 构建模块脚本
│   ├── patches/               # 补丁与自定义文件
│   ├── scripts/               # 更新与构建相关脚本
│   └── feeds/
├── output/                    # 编译产物目录
└── LICENSE
```

---

## 10. 使用建议

### 推荐构建顺序

```bash
./build.sh xiaomi-ax3000t config_preview
./build.sh xiaomi-ax3000t debug
./build.sh xiaomi-ax3000t normal
```

建议先用 `config_preview` 确认合并配置，再用 `debug` 核对最终配置，最后执行 `normal` 进行正式编译。

### 编译环境建议

- 使用 Ubuntu 22.04 / 24.04 LTS 更稳定
- 避免在低内存环境中直接执行大规模编译
- 优先在本地 Linux 文件系统上编译，而不是 NTFS / 挂载盘目录
- 若长时间构建失败，优先排查 `CONFIG_FRAGMENTS` 与 `make defconfig` 结果

---

## 11. 三方插件与 feeds

本项目使用 OpenWrt 的 feeds 机制接入第三方软件源，核心思路是：

- 通过 `feeds/` 配置管理第三方源
- 通过 `core/modules/*.sh` 调整 feeds 与 package 处理
- 对第三方包做定制修正，避免与官方源冲突

常见 source 例如：

```text
https://github.com/kenzok8/openwrt-packages
```

---

## 12. 常见问题

### 1）脚本提示“unsupported build mode”

请使用：

```bash
normal
debug
config_preview
```

不要传入其他模式名。

### 2）设备未显示

请检查：

- 是否存在同名的 `core/compilecfg/<device>.ini`
- 是否存在同名的 `core/deconfig/<device>.config`
- 两者是否命名一致

### 3）编译失败

优先排查：

- 依赖是否安装完整
- 设备配置是否正确
- 是否启用了错误的 `CONFIG_FRAGMENTS`
- 源码是否能正常 clone / checkout

---

## 13. 结论

`wrt-build` 适合用于 OpenWrt 路由器固件的批量化、可复现构建。它能够把设备配置、源码拉取、补丁注入、Feeds 处理和最终输出固件串联起来，让同一套构建脚本适用于多种设备。

如果你需要定制新的设备配置，通常只需要新增：

- `core/compilecfg/<new-device>.ini`
- `core/deconfig/<new-device>.config`

并在其中填写对应的上游仓库、分支和功能组件即可。

