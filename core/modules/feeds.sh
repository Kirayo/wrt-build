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
    append_feed "$FEEDS_PATH" "OpenAppFilter" "src-git OpenAppFilter https://github.com/destan19/OpenAppFilter.git"

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

override_feeds() {
    local config_file="$CORE_PATH/feeds/overrides.conf"

    [ -f "$config_file" ] || {
        echo "没有 feeds 覆盖配置，跳过"
        return 0
    }

    echo "正在处理第三方 feed 覆盖..."

    cd "${BUILD_PATH:-.}" || return 1

    while IFS='|' read -r feed package; do
        # 跳过空行和注释
        [ -z "$feed" ] && continue
        case "$feed" in
            \#*) continue ;;
        esac

        echo "覆盖 package: $package <- $feed"

        find package/feeds -maxdepth 2 \
            -type l \
            -name "$package" \
            -delete 2>/dev/null || true

        ./scripts/feeds install -p "$feed" -f "$package"
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