#!/usr/bin/env bash

set -Ee

# 错误处理
error_handler() {
    local exit_code=$?
    echo
    echo "ERROR:"
    echo "  Script : ${BASH_SOURCE[1]}"
    echo "  Line   : ${BASH_LINENO[0]}"
    echo "  Command: ${BASH_COMMAND}"
    echo "  Code   : $exit_code"
}

trap error_handler ERR

#######################################
# 参数
if [[ $# -lt 3 ]]; then
    echo "Usage:"
    echo "  $0 <repo_url> <branch> <build_dir> [commit_hash]"
    exit 1
fi

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4

#######################################
# 路径
# 以脚本自身定位，不依赖调用时的 CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# core
CORE_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
# 根
ROOT_PATH="$(cd "$CORE_PATH/.." && pwd)"
# 构建目录
BUILD_PATH="$(realpath "$ROOT_PATH/$BUILD_DIR")"
# 模块目录
MODULE_PATH="$(cd "$CORE_PATH/modules" && pwd)"

#######################################
# 默认ip地址
LAN_ADDR="192.168.0.1"

# 模块
# 按静态职责加载模块，执行顺序仍由本脚本统一控制。
source "$MODULE_PATH/network.sh"
source "$MODULE_PATH/repo.sh"
source "$MODULE_PATH/feeds.sh"
source "$MODULE_PATH/custom_feed.sh"
source "$MODULE_PATH/verify.sh"
source "$MODULE_PATH/docker.sh"
source "$MODULE_PATH/cups.sh"
source "$MODULE_PATH/feed_source_fixes.sh"
source "$MODULE_PATH/package_source_updates.sh"
source "$MODULE_PATH/target_fixes.sh"
source "$MODULE_PATH/luci_fixes.sh"
source "$MODULE_PATH/service_fixes.sh"

# 阶段顺序不可随意调整：feeds install 前后依赖的目录不同。
repo_checkout() {
    # 从干净的上游源码树开始，保证后续修正基线一致。
    clone_repo
    clean_up
    reset_feeds_conf
}

feeds_update() {
    FEEDS_PATH=$(get_feeds_path)
    append_feeds_from_file "$FEEDS_PATH" "$CORE_PATH/feeds/third_party_feeds.conf"
    update_feeds
    batch_prepare_pkg
}

stage_pre_install_source_fixes() {
    update_default_lan_addr
    set_build_signature
    check_default_settings
    remove_attendedsysupgrade
}

feeds_install() {
    # install 后才会生成 package/feeds/*。
    install_feeds
}

override_custom_feed() {
    override_feeds
    verify_feed_overrides
}

main() {
    repo_checkout
    feeds_update
    stage_pre_install_source_fixes
    feeds_install
    override_custom_feed
}

main "$@"
