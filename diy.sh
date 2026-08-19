#!/bin/bash
set -euo pipefail

# ==============================================================================
# 默认源码与分支
# ==============================================================================
WRT_REPO='https://github.com/VIKINGYFY/immortalwrt'
WRT_BRANCH='main'
# WRT_REPO='https://github.com/davidtall/immortalwrt'
# WRT_BRANCH='viking-main'

# ==============================================================================
# 参数解析
# $1: 配置文件路径，例如 Config/IPQ60XX-WIFI-YES.txt
# $2: 源码仓库地址，可选
# $3: 源码分支，可选
# ==============================================================================
if [ -n "${1:-}" ]; then
  filename=$(basename "$1")
  export WRT_CONFIG="${filename%.*}"
else
  export WRT_CONFIG="IPQ60XX-WIFI-YES"
fi

if [ -n "${2:-}" ]; then
  WRT_REPO="$2"
fi

if [ -n "${3:-}" ]; then
  WRT_BRANCH="$3"
fi

# ==============================================================================
# 环境变量
# ==============================================================================
export WRT_DIR=wrt
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"
export WRT_DATE=$(TZ=Asia/Shanghai date +"%y.%m.%d_%H.%M.%S")
export WRT_VER=$(echo "$WRT_REPO" | cut -d '/' -f 5-)-$WRT_BRANCH
export WRT_NAME='OWRT'
export WRT_SSID='OWRT'
export WRT_WORD='12345678'
export WRT_THEME='argon'
export WRT_IP='192.168.10.1'
export WRT_CI='WSL-OpenWRT-CI'
export CI_NAME='QCA-6.18-VIKINGYFY'

CONFIG_FILE="$GITHUB_WORKSPACE/Config/$WRT_CONFIG.txt"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config file not found: $CONFIG_FILE"
  exit 1
fi

export WRT_TYPE=$(sed -n "1{s/^#//;s/\r$//;p;q}" "$CONFIG_FILE")

# 【修复】分离 subtarget 与 device，防止路径拼接错误
export WRT_SUBTARGET=$(grep -m 1 -oP '^CONFIG_TARGET_[a-z0-9]+_\K[a-z0-9]+(?==y)' "$CONFIG_FILE")
export WRT_DEVICE=$(sed -n 's/^CONFIG_TARGET_DEVICE_.*_DEVICE_\([^=]*\)=y/\1/p' "$CONFIG_FILE" | head -n 1)
export WRT_ARCH="$WRT_SUBTARGET"

export WRT_TARGET=$(grep -m 1 -oP '^CONFIG_TARGET_\K[\w]+(?==y)' "$CONFIG_FILE" | tr '[:lower:]' '[:upper:]')

# ==============================================================================
# 加载公共函数
# ==============================================================================
if [ -f "$GITHUB_WORKSPACE/Scripts/function.sh" ]; then
  . "$GITHUB_WORKSPACE/Scripts/function.sh"
fi

chmod +x "$GITHUB_WORKSPACE"/Scripts/*.sh 2>/dev/null || true

# ==============================================================================
# 克隆或更新源码
# ==============================================================================
if [ ! -d "$WRT_DIR" ]; then
  git clone --depth=1 --single-branch --branch "$WRT_BRANCH" "$WRT_REPO" "$WRT_DIR"
  cd "$WRT_DIR"
else
  cd "$WRT_DIR"
  git remote set-url origin "$WRT_REPO" || true
  rm -rf feeds/*
  git fetch --depth=1 origin "$WRT_BRANCH"
  git checkout -B "$WRT_BRANCH" FETCH_HEAD
  git reset --hard FETCH_HEAD
  git clean -ffd
fi

# ==============================================================================
# 更新并安装 feeds
# ==============================================================================
./scripts/feeds update -a
./scripts/feeds install -a

# ==============================================================================
# 自定义包与设置
# ==============================================================================
cd package/
"$GITHUB_WORKSPACE/Scripts/Packages.sh"
"$GITHUB_WORKSPACE/Scripts/Handles.sh"
cd ..

generate_config
"$GITHUB_WORKSPACE/Scripts/Settings.sh"

# ==============================================================================
# 修补 stdcountof.h
# ==============================================================================
patch_stdcountof() {
  find . -type f \( -name "options.h" -o -name "Makefile.in" -o -name "Makefile.am" \) \
    -exec sed -i 's|#include <stdcountof\.h>|#define countof(a) (sizeof(a) / sizeof(*(a)))|g' {} + 2>/dev/null || true
  grep -rl "stdcountof.h" . 2>/dev/null | xargs -r sed -i 's|#include <stdcountof\.h>|#define countof(a) (sizeof(a) / sizeof(*(a)))|g' 2>/dev/null || true
}
patch_stdcountof

# ==============================================================================
# 生成最终配置
# ==============================================================================
make defconfig

echo "==================== final .config ===================="
grep -Ei 'ath11k|ipq-wifi|qrtr|mhi|pcie-qcom|wpad|hostapd|dnsmasq|fullcone|nf-flow|nft-offload|qca-nss|daed|sing-box' .config || true

# ==============================================================================
# 本地编译
# 默认只生成配置；如需编译，执行：
# BUILD=1 ./diy.sh Config/IPQ60XX-WIFI-YES.txt
# ==============================================================================
if [ "${BUILD:-0}" = "1" ]; then
  make download -j8 || make download -j1 V=s
  make -j$(nproc) || make -j1 V=s
fi