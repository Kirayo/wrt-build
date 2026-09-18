#!/usr/bin/env bash

FEEDS_CONF="feeds.conf.default"

get_feeds_path() {
    local feeds_path="$BUILD_PATH/$FEEDS_CONF"
    if [[ -f "$BUILD_PATH/feeds.conf" ]]; then
        feeds_path="$BUILD_PATH/feeds.conf"
    fi
    printf '%s\n' "$feeds_path"
}

# ============================================================
# 第三方 Feed 相关函数
# ============================================================

# 追加单条到目标 feeds 文件（去重）
# 用法: append_feed <目标feeds文件> <feed名> <完整src行>
append_feed() {
    local feeds_path="$1"
    local match_name="$2"
    local feed_entry="$3"

    [ -n "$feeds_path" ] && [ -n "$match_name" ] && [ -n "$feed_entry" ] || {
        echo "用法: append_feed <目标feeds文件> <feed名> <完整src行>" >&2
        return 1
    }

    [ -f "$feeds_path" ] || touch "$feeds_path"

    if grep -qE "^[[:space:]]*src-[^[:space:]]+[[:space:]]+${match_name}([[:space:]]|$)" "$feeds_path"; then
        echo "[SKIP] feed 已存在: $match_name"
        return 0
    fi

    if [ -s "$feeds_path" ]; then
        [ -z "$(tail -c 1 "$feeds_path" 2>/dev/null)" ] || echo "" >>"$feeds_path"
    fi

    echo "$feed_entry" >>"$feeds_path"
    echo "[OK] 已追加: $match_name"
}

# 把项目配置中的 feed 行追加到源码根 feeds.conf.default
# 用法: append_feeds_from_file <源码根/feeds.conf.default> <项目/feeds/third_party_feeds.conf>
append_feeds_from_file() {
    local target_feeds="$1"   # 源码根目录的 feeds.conf.default
    local conf_file="$2"      # 项目里的 feeds/third_party_feeds
    local line match_name

    [ -f "$conf_file" ] || {
        echo "警告: 找不到项目配置: $conf_file" >&2
        return 0
    }

    [ -f "$target_feeds" ] || touch "$target_feeds"

    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$line" in
            ''|\#*) continue ;;
            src-*) ;;
            *) continue ;;
        esac

        match_name=$(printf '%s' "$line" | awk '{print $2}')
        [ -n "$match_name" ] || continue

        append_feed "$target_feeds" "$match_name" "$line"
    done < "$conf_file"
}

update_feeds() {

    echo "正在更新 feeds 配置与索引..."
    # local FEEDS_PATH
    FEEDS_PATH=$(get_feeds_path)
    echo "FEEDS_PATH : $FEEDS_PATH"
    sed -i '/^#/d' "$FEEDS_PATH"
    sed -i '/[[:space:]]custom_feed[[:space:]]/d' "$FEEDS_PATH"

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

# 单包处理逻辑
prepare_single_pkg() {
    local repo_url="$1"
    local target_name="$2"
    local branch="$3"
    local clean_keywords="$4"

    local build_path="${BUILD_PATH:-.}"
    local feeds_path="$build_path/feeds"

    # 若未指定目录名，自动从 URL 提取
    if [ -z "$target_name" ]; then
        target_name=$(basename "$repo_url" .git)
    fi

    echo "=========================================="
    echo "🚀 正在处理插件: ${target_name} ${branch:+(分支: $branch)}"
    echo "=========================================="

    # 1. 清理 feeds 目录下冲突的旧版源码
    if [ -d "$feeds_path" ]; then
        echo "🧹 正在清理 feeds 目录下的冲突包..."
        [ -z "$clean_keywords" ] && clean_keywords="$target_name"

        for kw in $clean_keywords; do
            echo "   -> 移除包含 '${kw}' 关键词的目录"
            find "$feeds_path" -maxdepth 4 -type d -name "*${kw}*" 2>/dev/null | xargs -r rm -rf || true
        done
    fi

    # 2. 动态拼装 git clone 参数
    local clone_args=("--depth=1")
    if [ -n "$branch" ]; then
        clone_args+=("-b" "$branch")
    fi

    local dest_path="$build_path/package/$target_name"
    echo "📥 正在拉取源码至: $dest_path"
    rm -rf "$dest_path"

    # 执行 clone (自动展开 clone_args 数组)
    git clone "${clone_args[@]}" "$repo_url" "$dest_path"

    if [ "$target_name" = "luci-app-mosdns" ]; then
        setup_mosdns_no_geodata "$dest_path"
    fi

    echo "✅ [${target_name}] 准备完毕！"
    echo ""
}

# 逐行解析配置文件
batch_prepare_pkg() {
    local core_path="${CORE_PATH:-.}"
    local config_file="$core_path/feeds/packages.conf"

    if [ ! -f "$config_file" ]; then
        echo "❌ 错误: 找不到配置文件: $config_file"
        return 1
    fi

    echo "📋 开始读取配置文件: $config_file"
    echo ""

    # 解析 4 个字段: raw_url | raw_name | raw_branch | raw_keywords
    while IFS='|' read -r raw_url raw_name raw_branch raw_keywords || [ -n "$raw_url" ]; do
        local url target_name branch clean_keywords
        url=$(echo "$raw_url" | xargs)
        target_name=$(echo "$raw_name" | xargs)
        branch=$(echo "$raw_branch" | xargs)
        clean_keywords=$(echo "$raw_keywords" | xargs)

        # 忽略空行和 # 开头的注释行
        if [ -z "$url" ] || [[ "$url" =~ ^# ]]; then
            continue
        fi

        prepare_single_pkg "$url" "$target_name" "$branch" "$clean_keywords"
    done < "$config_file"

    echo "🎉 配置文件中的所有插件已全部拉取/预处理完毕！"
}

# 强制使用指定 feed 的某个包（通用函数）
# 用法: force_package_from_feed <feed名称> <包名称>
# 示例: force_package_from_feed kenzo luci-app-adguardhome
force_package_from_feed() {
    local feed_name="$1"
    local pkg_name="$2"

    if [ -z "$feed_name" ] || [ -z "$pkg_name" ]; then
        echo "❌ 错误: 用法 force_package_from_feed <feed名称> <包名称>"
        return 1
    fi

    echo "⚡ 正在强制使用 ${feed_name} 的 ${pkg_name}..."

    cd "${BUILD_PATH:-.}" || return 1

    # 1. 🧹 清理非目标 feeds 中的源码文件夹（排除目标 feed，防止误删源文件）
    find feeds -mindepth 2 -maxdepth 4 -name "$pkg_name" ! -path "feeds/$feed_name/*" -exec rm -rf {} + 2>/dev/null

    # 2. 🗑️ 清理 package/feeds 中的所有旧软链接/文件夹
    find package/feeds -maxdepth 3 -name "$pkg_name" -exec rm -rf {} + 2>/dev/null

    # 3. 🔗 强制从指定 feed 安装软链接
    ./scripts/feeds install -f -p "$feed_name" "$pkg_name"

    # 4. 🔍 验证软链接是否存在
    if [ -L "package/feeds/$feed_name/$pkg_name" ] || [ -d "package/feeds/$feed_name/$pkg_name" ]; then
        echo "✅ 已成功使用 ${feed_name}/${pkg_name}"
    else
        echo "⚠️ 警告: 未能确认 ${pkg_name} 来自 ${feed_name}，请检查 feeds 是否正确"
        return 1
    fi
}

# 🔄 批量强制使用指定 feed 的包
override_feeds() {
    local config_file="${CORE_PATH:-.}/feeds/overrides.conf"

    [ ! -f "$config_file" ] && return 0

    echo "🚀 正在处理强制指定源的包..."

    while IFS='|' read -r feed pkg || [ -n "$feed" ]; do
        # 跳过注释和空行
        [[ "$feed" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$feed" || -z "$pkg" ]] && continue

        # 去除前后空格
        feed=$(echo "$feed" | xargs)
        pkg=$(echo "$pkg" | xargs)

        force_package_from_feed "$feed" "$pkg"
    done < "$config_file"
}

# 🔍 检查覆盖结果
verify_feed_overrides() {
    local config_file="${CORE_PATH:-.}/feeds/overrides.conf"

    [ -f "$config_file" ] || return 0

    cd "${BUILD_PATH:-.}" || return 1

    echo "🔍 检查 feeds 覆盖结果..."

    local has_error=0
    while IFS='|' read -r feed package || [ -n "$feed" ]; do
        # 跳过注释和空行
        [[ "$feed" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$feed" || -z "$package" ]] && continue

        # 统一去除前后空格
        feed=$(echo "$feed" | xargs)
        package=$(echo "$package" | xargs)

        local path="package/feeds/$feed/$package"

        if [ -L "$path" ] || [ -d "$path" ]; then
            echo "  ✅ $package -> $feed"
        else
            echo "  ❌ $package 未正确来自 $feed"
            has_error=1
        fi
    done < "$config_file"

    return $has_error
}

# 移除luci-app-mosdns的v2ray-geodata、v2ray-geoip、v2ray-geosite依赖
setup_mosdns_no_geodata() {
    local package_path="$1"

    echo "DEBUG: package_path=[$package_path]"

    find "$package_path" -name "Makefile" -exec sed -i \
        -e 's/+v2ray-geodata//g' \
        -e 's/+v2ray-geoip//g' \
        -e 's/+v2ray-geosite//g' \
        {} +
}