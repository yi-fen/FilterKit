#!/usr/bin/env bash
#
# validate-ipa.sh — R4-E IPA 结构静态校验（离线/CI 可执行，不触真机）
#
# 校验目标：IPA 为标准 Payload 结构，内含设备 FilterKit.app，并复用设备构建静态校验。
# 无有效设备签名时，本包只能称"未签名 IPA 结构包"；本脚本不推定可安装性或权限放行。
#
# 用法：bash scripts/validate-ipa.sh <FilterKit.ipa>
# 输出：原始文本 + JSON 摘要（PACKAGE_VALIDATION_SUMMARY_PATH 可指定摘要路径）。

set -u
cd "$(dirname "$0")/.."

IPA_PATH="${1:-${IPA_PATH:-}}"
SUMMARY_PATH="${PACKAGE_VALIDATION_SUMMARY_PATH:-}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail=0
check_ids=()
check_names=()
check_status=()

record_check() {
  local id="$1" name="$2" status="$3"
  check_ids+=("$id"); check_names+=("$name"); check_status+=("$status")
  [ "$status" = "failed" ] && fail=1
}

# p1. IPA 文件存在且为 zip 归档
echo "== p1. IPA 存在且为 zip 归档 =="
if [ -z "$IPA_PATH" ] || [ ! -f "$IPA_PATH" ]; then
  echo "FAIL: IPA 缺失（IPA_PATH=${IPA_PATH:-<empty>}）"
  record_check "p1" "ipa archive exists" "failed"
elif command -v unzip >/dev/null 2>&1 && unzip -l "$IPA_PATH" >/dev/null 2>&1; then
  echo "OK: $(ls -la "$IPA_PATH" | awk '{print $5}') bytes"
  record_check "p1" "ipa archive exists" "passed"
else
  echo "FAIL: 非 zip 归档或缺少 unzip 工具"
  record_check "p1" "ipa archive exists" "failed"
fi

APP_IN_ARCHIVE=""
if [ -f "$IPA_PATH" ] && command -v unzip >/dev/null 2>&1; then
  APP_IN_ARCHIVE="$(unzip -Z1 "$IPA_PATH" | grep -E '^Payload/FilterKit\.app/$' | head -1)"
fi

# p2. Payload/FilterKit.app 结构存在
echo "== p2. Payload/FilterKit.app 结构存在 =="
if [ -n "$APP_IN_ARCHIVE" ]; then
  echo "OK: $APP_IN_ARCHIVE"
  record_check "p2" "payload app structure" "passed"
else
  echo "FAIL: 归档内未找到 Payload/FilterKit.app/"
  record_check "p2" "payload app structure" "failed"
fi

# p3. 解包后复用设备构建静态校验
echo "== p3. 设备产物静态校验（复用 validate-device-build） =="
if [ -n "$APP_IN_ARCHIVE" ] && command -v unzip >/dev/null 2>&1; then
  unzip -q "$IPA_PATH" -d "$WORKDIR"
  APP_PATH="$WORKDIR/Payload/FilterKit.app"
  if [ -d "$APP_PATH" ]; then
    if PACKAGE_VALIDATION_SUMMARY_PATH="" bash scripts/validate-device-build.sh "$APP_PATH"; then
      record_check "p3" "device app static validation" "passed"
    else
      record_check "p3" "device app static validation" "failed"
    fi
  else
    echo "FAIL: 解包后 FilterKit.app 缺失"
    record_check "p3" "device app static validation" "failed"
  fi
else
  echo "unavailable: 归档不可用或缺少 unzip，跳过设备产物校验"
  record_check "p3" "device app static validation" "unavailable"
fi

json_checks="["
for i in "${!check_ids[@]}"; do
  [ "$i" -gt 0 ] && json_checks+=","
  json_checks+="{\"id\":\"${check_ids[$i]}\",\"name\":\"${check_names[$i]}\",\"status\":\"${check_status[$i]}\"}"
done
json_checks+="]"
summary="{\"checks\":${json_checks},\"failed\":${fail},\"validator\":\"validate-ipa\"}"

echo "--- summary ---"
echo "$summary"
if [ -n "$SUMMARY_PATH" ]; then
  mkdir -p "$(dirname "$SUMMARY_PATH")"
  echo "$summary" > "$SUMMARY_PATH"
fi

exit "$fail"
