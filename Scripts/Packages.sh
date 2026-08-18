#!/bin/bash
set -euo pipefail

# ==============================================================================
# OpenWrt / ImmortalWrt 软件包管理脚本 (Packages.sh)
# ==============================================================================

# ------------------------------------------------------------------------------
# 更新 / 拉取软件包函数
# ------------------------------------------------------------------------------
UPDATE_PACKAGE() {
  local PKG_NAME=$1
  local PKG_REPO=$2
  local PKG_BRANCH=${3:-}
  local PKG_SPECIAL=${4:-}
  local PKG_LIST=("$PKG_NAME" ${5:-})
  local REPO_NAME=${PKG_REPO#*/}

  echo " "

  for NAME in "${PKG_LIST[@]}"; do
    echo "Search directory: $NAME"

    local FOUND_DIRS
    FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 4 -type d \( -name "$NAME" -o -name "luci-theme-$NAME" -o -name "luci-app-$NAME" \) 2>/dev/null || true)

    if [ -n "$FOUND_DIRS" ]; then
      while read -r DIR; do
        rm -rf "$DIR"
        echo "Delete directory: $DIR"
      done <<< "$FOUND_DIRS"
    else
      echo "Not found directory: $NAME"
    fi
  done

  rm -rf "$REPO_NAME"

  if [ -n "$PKG_BRANCH" ]; then
    if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"; then
      echo "Clone failed: https://github.com/$PKG_REPO.git branch: $PKG_BRANCH"
      return 1
    fi
  else
    if ! git clone --depth=1 --single-branch "https://github.com/$PKG_REPO.git"; then
      echo "Clone failed: https://github.com/$PKG_REPO.git"
      return 1
    fi
  fi

  if [[ "$PKG_SPECIAL" == "pkg" ]]; then
    find "./$REPO_NAME" -mindepth 2 -maxdepth 4 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \; 2>/dev/null || true
    rm -rf "./$REPO_NAME/"
  elif [[ "$PKG_SPECIAL" == "name" ]]; then
    mv -f "$REPO_NAME" "$PKG_NAME"
  fi
}

# ==============================================================================
# 1. 主力代理与实用工具拉取
# ==============================================================================

# 主力透明代理 DAED
UPDATE_PACKAGE "luci-app-daed" "QiuSimons/luci-app-daed" "kix"

# ==============================================================================
# 2. 清理官方 Feeds 中冲突的默认插件
# ==============================================================================
rm -rf ../feeds/luci/applications/luci-app-passwall*
rm -rf ../feeds/luci/applications/luci-app-mosdns*
rm -rf ../feeds/luci/applications/luci-app-dockerman*
rm -rf ../feeds/luci/applications/luci-app-bypass*

find ../package/feeds -maxdepth 4 \
  \( \
    -name 'luci-app-passwall*' \
    -o -name 'luci-app-mosdns*' \
    -o -name 'luci-app-dockerman*' \
    -o -name 'luci-app-bypass*' \
  \) -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# 3. 修复 luci-app-daed 编译配置
# ==============================================================================
if [ -f "luci-app-daed/daed/Makefile" ]; then
  sed -i 's/pnpm install ; \\/pnpm install --no-frozen-lockfile ; \\/g' luci-app-daed/daed/Makefile || true
  sed -i 's|github.com/daeuniverse/quic-go|github.com/olicesx/quic-go|g' luci-app-daed/daed/Makefile || true
fi

if [ -f "luci-app-daed/luci-app-daed/root/etc/init.d/luci_daed" ]; then
  chmod +x "luci-app-daed/luci-app-daed/root/etc/init.d/luci_daed" || true
fi

# ==============================================================================
# 4. 生成 DAED 启动时序 Hotplug 脚本 (WAN 口上线延迟启动)
# ==============================================================================
HOTPLUG_DIR="$GITHUB_WORKSPACE/wrt/files/etc/hotplug.d/iface"
mkdir -p "$HOTPLUG_DIR"

cat > "$HOTPLUG_DIR/99-daed-start" <<'EOF'
#!/bin/sh

[ "$ACTION" = "ifup" ] || exit 0
[ "$INTERFACE" = "wan" ] || exit 0
[ -x /etc/init.d/daed ] || exit 0

/etc/init.d/daed enabled || exit 0

sleep 20

wait=0
while [ $wait -lt 60 ]; do
  ping -4 -c1 -W2 223.5.5.5 >/dev/null 2>&1 && break
  sleep 3
  wait=$((wait + 3))
done

/etc/init.d/daed start
EOF

chmod +x "$HOTPLUG_DIR/99-daed-start"

# ==============================================================================
# 5. 同步自定义 package 目录到编译源码
# ==============================================================================
if [ -d "$GITHUB_WORKSPACE/package" ]; then
  cp -r "$GITHUB_WORKSPACE/package/." ./ 2>/dev/null || true
fi
