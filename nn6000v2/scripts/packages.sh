#!/usr/bin/env bash

GITHUB_BASE="https://github.com/"
OPENWRT_PACKAGES_DIR="$BUILD_DIR/feeds/openwrt_packages"

update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        if ! git clone --depth 1 -b $GOLANG_BRANCH $GOLANG_REPO ./feeds/packages/lang/golang; then
            echo "错误：克隆 golang 仓库 $GOLANG_REPO 失败" >&2
            exit 1
        fi
        echo "✓ golang 软件包更新完成"
    fi
}

clone_packages() {
    local name="$1"
    local repo_url="$2"
    local target_dir="$3"
    local sparse_pattern="${4:-}"
    local pre_cmd="${5:-}"
    local post_cmd="${6:-}"
    local move_from="${7:-}"
    local move_to="${8:-}"
    
    if [ -n "$pre_cmd" ]; then
        (cd "$BUILD_DIR" && eval "$pre_cmd") || exit 1
    fi
    
    rm -rf "$target_dir" 2>/dev/null || true
    
    if [ -n "$sparse_pattern" ]; then
        if ! git clone --filter=blob:none --no-checkout "$repo_url" "$target_dir"; then
            echo "错误：从 $repo_url 克隆 $name 仓库失败" >&2
            exit 1
        fi
        
        pushd "$target_dir" >/dev/null
        git sparse-checkout init --cone
        if ! git sparse-checkout set $sparse_pattern; then
            echo "错误：稀疏检出 $sparse_pattern 失败" >&2
            popd >/dev/null
            exit 1
        fi
        git checkout --quiet
        popd >/dev/null
        
        if [ -n "$move_from" ] && [ -n "$move_to" ]; then
            rm -rf "$move_to" 2>/dev/null || true
            mv "$move_from" "$move_to" || exit 1
        fi
    else
        if ! git clone --depth=1 "$repo_url" "$target_dir"; then
            echo "错误：从 $repo_url 克隆 $name 仓库失败" >&2
            exit 1
        fi
    fi
    
    if [ -n "$post_cmd" ]; then
        (cd "$BUILD_DIR" && eval "$post_cmd") || exit 1
    fi
    
    echo "✓ $name 克隆完成"
}

install_openwrt_packages() {
    ./scripts/feeds install -p openwrt_packages -f \
        luci-theme-argon luci-app-argon-config \
        luci-app-homeproxy \
        luci-app-tailscale-community
}

clone_homeproxy() {
    clone_packages "luci-app-homeproxy" \
        "${GITHUB_BASE}szwjp/luci-app-homeproxy.git" \
        "$OPENWRT_PACKAGES_DIR/luci-app-homeproxy"
}

remove_attendedsysupgrade() {
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
            echo "Removed luci-app-attendedsysupgrade from $makefile"
        fi
    done
}

clone_luci_tailscale() {
    local TEMP_DIR="$OPENWRT_PACKAGES_DIR/luci-app-tailscale-community-temp"
    local TARGET_DIR="$OPENWRT_PACKAGES_DIR/luci-app-tailscale-community"
    
    clone_packages "luci-app-tailscale-community" \
        "${GITHUB_BASE}Tokisaki-Galaxy/luci-app-tailscale-community.git" \
        "$TEMP_DIR" \
        "" \
        "" \
        "rm -rf \"$TARGET_DIR\" 2>/dev/null || true; mv \"$TEMP_DIR/luci-app-tailscale-community\" \"$TARGET_DIR\"; rm -rf \"$TEMP_DIR\""
}
