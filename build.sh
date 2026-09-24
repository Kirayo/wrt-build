#!/usr/bin/env bash

set -e

# 以脚本自身定位，不依赖调用时的 CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/modules/network.sh" ]]; then
    CORE_PATH="$SCRIPT_DIR"
elif [[ -f "$SCRIPT_DIR/core/modules/network.sh" ]]; then
    CORE_PATH="$(cd "$SCRIPT_DIR/core" && pwd)"
else
    echo "Error: core not found (from $SCRIPT_DIR)" >&2
    exit 1
fi


# 根目录
ROOT_PATH=$(cd "$CORE_PATH/.." && pwd)

DEVICE=$1
MODE=$2

BUILD_DATE=${BUILD_DATE:-$(TZ=Asia/Shanghai date +"%Y-%m-%d")}
BUILD_TIME=${BUILD_TIME:-$(TZ=Asia/Shanghai date +"%H:%M:%S")}

echo "================================"
echo "Device      : $DEVICE"
echo "Date        : $BUILD_DATE"
echo "Time        : $BUILD_TIME"
echo "Mode        : $MODE"
echo "================================"

SUPPORTED_DEVS=()

# 只有 compilecfg 与 deconfig 同名成对存在的设备才可构建。
collect_supported_devs() {
    local ini_file
    local dev_key
    local IFS

    SUPPORTED_DEVS=()

    for ini_file in "$CORE_PATH"/compilecfg/*.ini; do
        [[ -f "$ini_file" ]] || continue

        dev_key=$(basename "$ini_file" .ini)
        if [[ -f "$CORE_PATH/deconfig/$dev_key.config" ]]; then
            SUPPORTED_DEVS+=("$dev_key")
        fi
    done

    if [[ ${#SUPPORTED_DEVS[@]} -eq 0 ]]; then
        return
    fi

    IFS=$'\n' SUPPORTED_DEVS=($(printf '%s\n' "${SUPPORTED_DEVS[@]}" | LC_ALL=C sort))
}

print_usage() {
    echo "Usage: $0 <device> [normal|debug|config_preview]"
    echo "       ./build.sh"
}

print_supported_devs() {
    local index

    echo "Supported devices:"
    for ((index = 0; index < ${#SUPPORTED_DEVS[@]}; index++)); do
        printf "  %d) %s\n" "$((index + 1))" "${SUPPORTED_DEVS[index]}"
    done
}

prompt_select_dev() {
    local input
    local selected_index

    while true; do
        print_supported_devs
        printf "Select device by number (q to quit): "

        if ! read -r input; then
            echo
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*[qQ][[:space:]]*$ ]]; then
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            selected_index=${BASH_REMATCH[1]}
            if ((selected_index >= 1 && selected_index <= ${#SUPPORTED_DEVS[@]})); then
                DEVICE=${SUPPORTED_DEVS[selected_index - 1]}
                return
            fi
        fi

        echo "Invalid selection. Please enter a number between 1 and ${#SUPPORTED_DEVS[@]}."
    done
}

prompt_select_build_mode() {
    local input

    while true; do
        echo "Build mode:"
        echo "  1) normal"
        echo "  2) debug"
        echo "  3) config_preview"
        printf "Select build mode (1-5, q to quit): "

        if ! read -r input; then
            echo
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*[qQ][[:space:]]*$ ]]; then
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*1[[:space:]]*$ ]]; then
            MODE="normal"
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*2[[:space:]]*$ ]]; then
            MODE="debug"
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*3[[:space:]]*$ ]]; then
            MODE="config_preview"
            return
        fi

        echo "Invalid selection. Please enter 1, 2, 3"
    done
}
# 判断是否支持交互终端
is_interactive_terminal() {
    [[ -t 0 && -t 1 ]]
}
# 校验模式
validate_build_mode() {
    case "$MODE" in
        normal|debug|config_preview)
            return 0
            ;;
        *)
            echo "Error: unsupported build mode: $MODE" >&2
            print_usage >&2
            exit 1
            ;;
    esac
}

if [[ $# -eq 0 ]]; then
    collect_supported_devs

    if [[ ${#SUPPORTED_DEVS[@]} -eq 0 ]]; then
        echo "Error: no supported devices found."
        exit 1
    fi

    if ! is_interactive_terminal; then
        print_usage
        print_supported_devs
        exit 1
    fi

    prompt_select_dev

    if [[ -z $MODE ]]; then
        prompt_select_build_mode
    fi
fi

CONFIG_FILE="$CORE_PATH/deconfig/$DEVICE.config"
INI_FILE="$CORE_PATH/compilecfg/$DEVICE.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

validate_build_mode

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

CONFIG_FRAGMENT_DIR="$CORE_PATH/deconfig/fragments"
CONFIG_FRAGMENTS=()

parse_fragment_csv() {
    local csv=$1
    local output_array=$2
    local item
    local -n target_array="$output_array"

    target_array=()
    csv=${csv//[[:space:]]/}

    [[ -n $csv ]] || return 0

    IFS=',' read -r -a target_array <<< "$csv"

    for item in "${target_array[@]}"; do
        if [[ -z $item ]]; then
            echo "Error: empty config fragment name in '$csv'." >&2
            exit 1
        fi

        if [[ ! $item =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            echo "Error: invalid config fragment name '$item'." >&2
            exit 1
        fi
    done
}

validate_enable_fragment() {
    local fragment=$1
    local fragment_path="$CONFIG_FRAGMENT_DIR/$fragment.config"

    if [[ ! -f $fragment_path ]]; then
        echo "Error: config fragment not found: $fragment_path" >&2
        exit 1
    fi
}

join_fragments() {
    local IFS=','
    echo "$*"
}

# 校验 CONFIG_FRAGMENTS 是否有效
resolve_config_fragments() {
    local fragment

    parse_fragment_csv "$(read_ini_by_key "CONFIG_FRAGMENTS")" CONFIG_FRAGMENTS

    for fragment in "${CONFIG_FRAGMENTS[@]}"; do
        validate_enable_fragment "$fragment"
    done

}

print_config_fragment_summary() {
    echo ""
    echo "Config fragments:"
    echo "  Device: $DEVICE"
    echo "  Enabled fragments: $(join_fragments "${CONFIG_FRAGMENTS[@]}")"
}

print_config_preview() {
    print_config_fragment_summary
    echo "Config assembly order:"
    echo "  1) $CONFIG_FILE"
    echo "  2) $CORE_PATH/deconfig/base.config"

    local order=3
    local fragment
    for fragment in "${CONFIG_FRAGMENTS[@]}"; do
        echo "  $order) $CONFIG_FRAGMENT_DIR/$fragment.config"
        order=$((order + 1))
    done

}

apply_repo_modifications() {
    # 1. 动态确定基准路径（优先使用 $BUILD_PATH，若未定义则自动使用当前目录 .）
    local base_path="${BUILD_PATH:-.}"
    local target_script="$base_path/package/emortal/default-settings/files/99-default-settings-chinese"

    if [ -f "$target_script" ]; then
        echo "====> 正在修改 $target_script <===="

        # 2. 清理原脚本末尾的 exit 0（防止追加代码被跳过）
        sed -i '/^exit 0/d' "$target_script"

        # 3. 追加干净的修剪逻辑（使用 EOF 保持代码格式完整，内部复用 repo_file 变量）
        cat << 'EOF' >> "$target_script"

# --- 自定义软件源修剪与镜像替换逻辑 (兼容 APK & OPKG) ---
for repo_file in "/etc/apk/repositories.d/distfeeds.list" "/etc/apk/repositories" "/etc/opkg/distfeeds.conf"; do
    if [ -f "$repo_file" ]; then
        # 剔除 NSS 冲突包源
        sed -i '/nss_packages/d' "$repo_file"
        sed -i '/sqm_scripts_nss/d' "$repo_file"

        # 替换特定 video 镜像源地址为交大源
        sed -i '/\/video/s|https://[^/]*/|https://mirror.sjtu.edu.cn/|g' "$repo_file"
    fi
done

exit 0
EOF
        echo "====> 修改完成！已成功注入修剪逻辑 <===="
    else
        echo "====> 警告: 未找到文件 $target_script，跳过修改 <===="
    fi
}

# 关闭自动挂载
setup_disable_automount() {
    local ROOT="${BUILD_PATH:-.}"
    ROOT="$(cd "$ROOT" 2>/dev/null && pwd || echo "$ROOT")"

    mkdir -p "${ROOT}/files/etc/config"
    cat > "${ROOT}/files/etc/config/fstab" << 'EOF'
config global
	option anon_swap '0'
	option anon_mount '0'
	option auto_swap '0'
	option auto_mount '0'
	option delay_root '5'
	option check_fs '0'
EOF
    echo "[OK] 已写入 ${ROOT}/files/etc/config/fstab（关闭自动挂载）"
}

# 汇总配置文件
assemble_config() {
    local fragment
    local config_path="$BUILD_PATH/.config"

    # 1. 先清空（或重新创建）目标 .config 文件
    > "$config_path"

    # 2. 先写入公共基础配置 base.config
    if [ -f "$CORE_PATH/deconfig/base.config" ]; then
        cat "$CORE_PATH/deconfig/base.config" >> "$config_path"
        echo "" >> "$config_path"  # 追加换行，防止与后续片段黏连
    fi

    # 3. 接着追加各种功能片段配置 (CONFIG_FRAGMENTS)
    for fragment in "${CONFIG_FRAGMENTS[@]}"; do
        if [ -f "$CONFIG_FRAGMENT_DIR/$fragment.config" ]; then
            cat "$CONFIG_FRAGMENT_DIR/$fragment.config" >> "$config_path"
            echo "" >> "$config_path"  # 每个片段追加完后强制换行
        fi

        # 记录是否包含 no-usb（不要在循环里反复执行）
        if [ "$fragment" = "no-usb" ]; then
            enable_no_usb=1
        fi
    done

    # 4. 最后追加主配置文件 CONFIG_FILE（确保它的优先级最高，覆盖前面的重复项）
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE" >> "$config_path"
        echo "" >> "$config_path"  # 确保文件结尾有换行
    fi

    # 5. 仅当本次启用了 no-usb 时，关闭自动挂载（只执行一次）
    if [ "$enable_no_usb" -eq 1 ]; then
        setup_disable_automount
    fi
}

# 从 third_party_feeds 配置文件解析出 feed 名列表
# 用法: _parse_third_party_feed_names <配置文件>
# 输出: 空格分隔的 feed 名
_parse_third_party_feed_names() {
    local conf_file="$1"
    local line name
    local names=""

    [ -f "$conf_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$line" in
            ''|\#*) continue ;;
            src-*) ;;
            *) continue ;;
        esac
        name=$(printf '%s' "$line" | awk '{print $2}')
        [ -n "$name" ] || continue
        names="${names} ${name}"
    done < "$conf_file"

    # 去掉首尾空格
    printf '%s' "$names" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# 在 .config 中关闭 CONFIG_FEED_* 导出
# 用法: setup_disable_config_feeds [源码根] [third_party_feeds路径]
setup_disable_config_feeds() {
    local ROOT="${1:-${BUILD_PATH:-.}}"
    local conf_file="${2:-${CORE_PATH}/feeds/third_party_feeds.conf}"
    local CFG feeds name

    ROOT="$(cd "$ROOT" 2>/dev/null && pwd || echo "$ROOT")"
    CFG="${ROOT}/.config"
    feeds=$(_parse_third_party_feed_names "$conf_file")

    [ -f "$CFG" ] || {
        echo "[SKIP] 无 .config，跳过 CONFIG_FEED 处理"
        return 0
    }

    if [ -z "$feeds" ]; then
        echo "[SKIP] 未从 $conf_file 解析到 feed 名"
        return 0
    fi

    for name in $feeds; do
        sed -i "/CONFIG_FEED_${name}=/d" "$CFG"
        sed -i "/CONFIG_FEED_${name} is not set/d" "$CFG"
        echo "# CONFIG_FEED_${name} is not set" >> "$CFG"
    done

    echo "[OK] 已在 .config 禁用 CONFIG_FEED: $feeds"
}

# 读取设备元信息，确定上游源码和构建目录。
REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}
# 构建目录
BUILD_PATH="$(realpath "$ROOT_PATH/$BUILD_DIR")"

resolve_config_fragments

if [[ $MODE == "config_preview" ]]; then
    print_config_preview
    exit 0
fi

# 构建准备
"$CORE_PATH/scripts/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_DIR" "$COMMIT_HASH"

cd "$BUILD_PATH"
# 构建目录
if [[ "$GITHUB_ACTIONS" == "true" && -z "$BUILD_DIR" ]]; then
    BUILD_DIR="actions-build"
fi

if [[ -z "$BUILD_DIR" ]]; then
    echo "Error: BUILD_DIR is not set" >&2
    exit 1
fi

# 合并处理config
assemble_config
print_config_fragment_summary


# x86 feed 修正
if grep -qE "^CONFIG_TARGET_x86_64=y" "$BUILD_PATH/.config"; then
    DISTFEEDS_PATH="$BUILD_PATH/package/emortal/default-settings/files/99-distfeeds.conf"

    if [[ -f "$DISTFEEDS_PATH" ]]; then
        echo "Fix x86_64 distfeeds"
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi

echo "Running make defconfig"
make defconfig

if [[ "$MODE" == "debug" ]]; then
    DEBUG_DIR="$ROOT_PATH/output/debug"
    mkdir -p "$DEBUG_DIR"

    # Export diffconfig
    "$BUILD_PATH/scripts/diffconfig.sh" \
        > "$DEBUG_DIR/${DEVICE}.diffconfig"

    # Export complete config after make defconfig
    cp "$BUILD_PATH/.config" \
        "$DEBUG_DIR/${DEVICE}.config"

    echo "========== OUTPUT =========="
    echo "Diffconfig : $DEBUG_DIR/${DEVICE}.diffconfig"
    echo "Config     : $DEBUG_DIR/${DEVICE}.config"

    exit 0
fi

# ==============================
# Build前
# ==============================
setup_disable_config_feeds
apply_repo_modifications

# Cleanup old images
TARGET_DIR="$BUILD_PATH/bin/targets"

if [[ -d "$TARGET_DIR" ]]; then
   rm -rf "$TARGET_DIR"
fi

# ==============================
# Build
# ==============================
CPU_CORES=$(nproc)
DOWNLOAD_JOBS=$((CPU_CORES * 2))
BUILD_JOBS=$((CPU_CORES + 1))

# 防止异常环境 nproc 失败
[ "$CPU_CORES" -ge 1 ] 2>/dev/null || CPU_CORES=1
[ "$DOWNLOAD_JOBS" -ge 1 ] || DOWNLOAD_JOBS=2
[ "$BUILD_JOBS" -ge 1 ] || BUILD_JOBS=1

echo "CPU cores     : $CPU_CORES"
echo "Download jobs: $DOWNLOAD_JOBS"
echo "Build jobs   : $BUILD_JOBS"

make download -j"$DOWNLOAD_JOBS"

# 先并行；失败再单线程出完整日志
if ! make -j"$BUILD_JOBS"; then
    echo "并行编译失败，改用 -j1 V=s 重试以便定位错误..."
    make -j1 V=s
fi

# ==============================
# Build Artifacts
# ==============================
echo "================================"
echo " 编译后文件列表："
ls -lh "$TARGET_DIR"
echo "================================"

OUTPUT_DIR="$ROOT_PATH/output"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

while IFS= read -r file; do

    cp "$file" "$OUTPUT_DIR/"

done < <(
    find "$TARGET_DIR" -type f \
    -not -path "*/packages/*"
)

echo
echo "================================"
echo " 输出目录: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
echo "================================"