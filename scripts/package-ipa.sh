#!/usr/bin/env bash
#
# package-ipa.sh — R4-C IPA 结构打包草稿（离线/CI 可执行；不做设备签名）
#
# 输入：设备构建产物 FilterKit.app（R4-A）；输出：标准 Payload 结构 IPA。
# 注意：未经过有效设备签名的产物只能称"未签名 IPA 结构包"，不能称可安装 IPA；
# 本脚本不做证书/描述文件签名，不推定设备可安装性或权限放行。
#
# 用法：
#   APP_PATH=<FilterKit.app> OUT_IPA=build/IPA/FilterKit.ipa bash scripts/package-ipa.sh

set -u
cd "$(dirname "$0")/.."

APP_PATH="${APP_PATH:-${1:-}}"
OUT_IPA="${OUT_IPA:-build/IPA/FilterKit.ipa}"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "::error::APP_PATH 未提供或不存在：${APP_PATH:-<empty>}"
  exit 1
fi
if [ ! -f "$APP_PATH/FilterKit" ] || [ ! -f "$APP_PATH/Info.plist" ]; then
  echo "::error::$APP_PATH 不是完整 FilterKit.app（缺 FilterKit 二进制或 Info.plist）"
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

STAGE="$WORKDIR/IPA/Payload"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/FilterKit.app"

mkdir -p "$(dirname "$OUT_IPA")"
rm -f "$OUT_IPA"
OUT_ABS="$(cd "$(dirname "$OUT_IPA")" && pwd)/$(basename "$OUT_IPA")"

if command -v zip >/dev/null 2>&1; then
  (cd "$WORKDIR/IPA" && zip -qr "$OUT_ABS" Payload)
  echo "IPA 结构包已生成（未签名）：$OUT_ABS"
  echo "注意：未签名 IPA 结构包不等于可安装 IPA；设备签名须在 R4-B 核实路线后完成。"
else
  echo "::warning::缺少 zip 工具，仅完成解包暂存（${STAGE}），未生成 IPA"
  exit 1
fi
