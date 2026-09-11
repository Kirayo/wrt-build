#!/usr/bin/env bash

get_feeds_path() {
    local feeds_path="$BUILD_PATH/$FEEDS_CONF"
    if [[ -f "$BUILD_PATH/feeds.conf" ]]; then
        feeds_path="$BUILD_PATH/feeds.conf"
    fi
    printf '%s\n' "$feeds_path"
}

append_feed() {
    local feeds_path="$1"
    local match_pattern="$2"
    local feed_entry="$3"

    # 1. 确保目标文件存在
    [ -f "$feeds_path" ] || touch "$feeds_path"

    # 2. 精确匹配：仅匹配未被注释且名称完全相同的 feed 行
    # 匹配规则：行首可有空格 -> src-xxx -> 空格 -> 准确的 feed 名称 -> 空格或行尾
    if ! grep -qE "^[[:space:]]*src-[^[:space:]]+[[:space:]]+${match_pattern}([[:space:]]|$)" "$feeds_path"; then
        # 3. 如果文件末尾没有换行符，自动补全换行（保留原巧妙逻辑，屏蔽潜在 stderr）
        [ -z "$(tail -c 1 "$feeds_path" 2>/dev/null)" ] || echo "" >>"$feeds_path"

        # 4. 追加新源
        echo "$feed_entry" >>"$feeds_path"
    fi
}

update_feeds() {

    # # 调试

    # sed -i '/packages_ext/d' "$FEEDS_PATH"
    # sed -i '/[[:space:]]small8[[:space:]]/d' "$FEEDS_PATH"

    # append_feed "$FEEDS_PATH" "openwrt_bandix" "src-git openwrt_bandix https://github.com/timsaya/openwrt-bandix.git;main"
    # append_feed "$FEEDS_PATH" "luci_app_bandix" "src-git luci_app_bandix https://github.com/timsaya/luci-app-bandix.git;main"

    # if [ ! -f "$BUILD_PATH/include/bpf.mk" ]; then
    #     touch "$BUILD_PATH/include/bpf.mk"
    # fi

    echo "正在更新 feeds 配置与索引..."
    # local FEEDS_PATH
    FEEDS_PATH=$(get_feeds_path)
    echo "FEEDS_PATH : $FEEDS_PATH"
    sed -i '/^#/d' "$FEEDS_PATH"
    sed -i '/[[:space:]]custom_feed[[:space:]]/d' "$FEEDS_PATH"

    append_feed "$FEEDS_PATH" "kenzo" "src-git kenzo https://github.com/kenzok8/openwrt-packages.git"

    # 确保切换到正确的源码根目录
    cd "${BUILD_PATH:-.}" || return 1

    # 彻底清理旧的 feeds 缓存文件夹，确保没有残留的旧驱动
    rm -rf ./feeds/

    # 使用 -f -a 强制更新所有源，防止 git 冲突导致 CI 中断
    ./scripts/feeds update -f -a
}

install_feeds() {
    echo "正在安装所有 feeds 软件包..."

    # 确保在源码根目录下执行
    cd "${BUILD_PATH:-.}" || return 1

    # 配合 -f 强制重新建立符号链接，覆盖旧的同名包
    ./scripts/feeds install -f -a
}

prepare_oaf() {
    local feeds_path
    feeds_path="$BUILD_PATH/feeds"

    echo "正在清理默认旧版 OpenAppFilter..."

    # 删除 ImmortalWrt / LibWrt 默认集成的旧版
    rm -rf "$feeds_path/packages/net/open-app-filter"
    rm -rf "$feeds_path/luci/applications/luci-app-appfilter"

    # 保险清理可能残留的目录
    find "$feeds_path" -type d \( -name "*appfilter*" -o -name "*oaf*" \) 2>/dev/null | xargs -r rm -rf || true

    # 添加官方最新版
    local oaf_path="$BUILD_PATH/package/OpenAppFilter"

    echo "正在准备官方最新版 OpenAppFilter..."

    rm -rf "$oaf_path"

    git clone \
        --depth=1 \
        https://github.com/destan19/OpenAppFilter.git \
        "$oaf_path"
}

# 强制使用指定 feed 的某个包（通用函数）
# 用法: force_package_from_feed <feed名称> <包名称>
# 示例: force_package_from_feed kenzo luci-app-adguardhome
force_package_from_feed() {
    local feed_name="$1"
    local pkg_name="$2"

    if [ -z "$feed_name" ] || [ -z "$pkg_name" ]; then
        echo "错误: 用法 force_package_from_feed <feed名称> <包名称>"
        return 1
    fi

    echo "正在强制使用 ${feed_name} 的 ${pkg_name}..."

    # 1. 删除所有其他地方可能存在的同名包
    cd "${BUILD_PATH:-.}" || return 1
    rm -rf feeds/*/="$pkg_name"
    rm -rf package/feeds/*/="$pkg_name"
    find feeds package/feeds -type d -name "$pkg_name" 2>/dev/null | xargs -r rm -rf

    # 2. 只从指定 feed 安装
    ./scripts/feeds install -p "$feed_name" "$pkg_name"

    # 3. 简单验证
    if [ -d "package/feeds/$feed_name/$pkg_name" ] || [ -L "package/feeds/$feed_name/$pkg_name" ]; then
        echo "✓ 已成功使用 ${feed_name}/${pkg_name}"
    else
        echo "⚠ 警告: 未能确认 ${pkg_name} 来自 ${feed_name}，请检查 feeds 是否正确"
    fi
}

# 批量强制使用指定 feed 的包
# 配置文件格式：feed名|包名
override_feeds() {
    local config_file="$CORE_PATH/feeds/overrides.conf"

    [ ! -f "$config_file" ] && return 0

    echo "正在处理强制指定源的包..."

    while IFS='|' read -r feed pkg || [ -n "$feed" ]; do
        # 跳过注释和空行
        [[ "$feed" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$feed" || -z "$pkg" ]] && continue

        feed=$(echo "$feed" | xargs)
        pkg=$(echo "$pkg" | xargs)

        force_package_from_feed "$feed" "$pkg"
    done < "$config_file"
}

verify_feed_overrides() {
    local config_file="$CORE_PATH/feeds/overrides.conf"

    [ -f "$config_file" ] || return 0

    cd "${BUILD_PATH:-.}" || return 1

    echo "检查 feeds 覆盖结果..."

    while IFS='|' read -r feed package; do
        [ -z "$feed" ] && continue

        case "$feed" in
            \#*) continue ;;
        esac

        local path="package/feeds/$feed/$package"

        if [ -L "$path" ]; then
            echo "  ✓ $package -> $feed"
        else
            echo "  ✗ $package 未正确来自 $feed"
            return 1
        fi
    done < "$config_file"
}