#!/usr/bin/env bash
#
# validate-device-build.sh — R4-E 设备构建静态校验（离线/CI 可执行，不触真机）
#
# 校验目标：一个 iOS 设备（iphoneos）FilterKit.app 产物的平台、架构、Bundle ID 与结构。
# 本脚本只证明包产物符合部署要求，不代表 RootHide 真机权限、真实加载或 jbroot() 可调用。
#
# 用法：
#   APP_PATH=build/DerivedData/Build/Products/Release-iphoneos/FilterKit.app \
#     bash scripts/validate-device-build.sh
# 或：bash scripts/validate-device-build.sh <FilterKit.app 路径>
#
# 输出：原始文本 + 机器可读 JSON 摘要；设置 PACKAGE_VALIDATION_SUMMARY_PATH 时摘要写入该文件。
# 退出码：0 = 未发现失败项；非 0 = 存在 failed 项。工具链缺失的检查记 unavailable，不计 failed。

set -u
cd "$(dirname "$0")/.."

APP_PATH="${1:-${APP_PATH:-}}"
SUMMARY_PATH="${PACKAGE_VALIDATION_SUMMARY_PATH:-}"

fail=0
check_ids=()
check_names=()
check_status=()

record_check() {
  local id="$1" name="$2" status="$3"
  check_ids+=("$id")
  check_names+=("$name")
  check_status+=("$status")
  if [ "$status" = "failed" ]; then fail=1; fi
}

read_plist() {
  # $1 = plist 路径；$2 = key；优先 plutil（同行 => 取值），其次 defaults。缺工具链返回空。
  local plist="$1" key="$2"
  if command -v plutil >/dev/null 2>&1; then
    plutil -p "$plist" 2>/dev/null \
      | grep -E "\"$key\"" \
      | sed -E 's/.*=> ?//; s/^"|"$//g'
  elif command -v defaults >/dev/null 2>&1; then
    defaults read "$plist" "$key" 2>/dev/null
  else
    return 1
  fi
}

# d1. App 目录存在
echo "== d1. FilterKit.app 目录存在 =="
if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
  echo "OK: $APP_PATH"
  record_check "d1" "device app bundle exists" "passed"
else
  echo "FAIL: FilterKit.app 目录缺失（APP_PATH=${APP_PATH:-<empty>}）"
  record_check "d1" "device app bundle exists" "failed"
fi

BINARY="$APP_PATH/FilterKit"
INFO_PLIST="$APP_PATH/Info.plist"

# d2. 主二进制存在且为 Mach-O
echo "== d2. 主二进制存在且为 Mach-O =="
if [ -f "$BINARY" ]; then
  if command -v file >/dev/null 2>&1 && file "$BINARY" | grep -q "Mach-O"; then
    echo "OK: $(file -b "$BINARY")"
    record_check "d2" "main binary Mach-O" "passed"
  elif command -v file >/dev/null 2>&1; then
    echo "FAIL: 二进制非 Mach-O：$(file -b "$BINARY")"
    record_check "d2" "main binary Mach-O" "failed"
  else
    echo "unavailable: 无 file 工具，仅确认二进制存在"
    record_check "d2" "main binary Mach-O" "unavailable"
  fi
else
  echo "FAIL: 主二进制缺失：$BINARY"
  record_check "d2" "main binary Mach-O" "failed"
fi

# d3. 平台必须为 iPhoneOS（不是 iPhoneSimulator）
echo "== d3. 平台为 iPhoneOS =="
if [ -f "$INFO_PLIST" ] && command -v plutil >/dev/null 2>&1; then
  platform="$(read_plist "$INFO_PLIST" DTPlatformName)"
  if [ "$platform" = "iphoneos" ]; then
    echo "OK: DTPlatformName=iphoneos"
    record_check "d3" "platform iPhoneOS" "passed"
  else
    echo "FAIL: DTPlatformName=${platform:-<empty>}（模拟器产物不可作设备包）"
    record_check "d3" "platform iPhoneOS" "failed"
  fi
else
  echo "unavailable: 缺少 Info.plist 或 plutil，平台无法判定"
  record_check "d3" "platform iPhoneOS" "unavailable"
fi

# d4. 架构包含 arm64（arm64e 视目标环境，不强制）
echo "== d4. 架构包含 arm64 =="
if [ -f "$BINARY" ] && command -v lipo >/dev/null 2>&1; then
  lipo_info="$(lipo -info "$BINARY" 2>/dev/null)"
  echo "$lipo_info"
  if echo "$lipo_info" | grep -E "arm64( |$|e)" ; then
    case "$lipo_info" in
      *arm64*) record_check "d4" "architecture includes arm64" "passed" ;;
      *) record_check "d4" "architecture includes arm64" "failed" ;;
    esac
  else
    record_check "d4" "architecture includes arm64" "failed"
  fi
else
  echo "unavailable: 无 lipo 工具或二进制缺失，架构无法判定"
  record_check "d4" "architecture includes arm64" "unavailable"
fi

# d5. Bundle ID 与草案一致（B3 未冻结前按 com.filterkit.manager）
echo "== d5. Bundle ID 一致 =="
EXPECTED_BUNDLE="com.filterkit.manager"
if [ -f "$INFO_PLIST" ] && command -v plutil >/dev/null 2>&1; then
  bundle="$(read_plist "$INFO_PLIST" CFBundleIdentifier | tr -d ' "')"
  if [ "$bundle" = "$EXPECTED_BUNDLE" ]; then
    echo "OK: CFBundleIdentifier=$bundle"
    record_check "d5" "bundle identifier matches draft" "passed"
  else
    echo "FAIL: CFBundleIdentifier=${bundle:-<empty>}，期望 $EXPECTED_BUNDLE"
    record_check "d5" "bundle identifier matches draft" "failed"
  fi
else
  echo "unavailable: 缺少 Info.plist 或 plutil，Bundle ID 无法判定"
  record_check "d5" "bundle identifier matches draft" "unavailable"
fi

# d6. 最低系统版本已记录（兼容交集待真机实测）
echo "== d6. MinimumOSVersion 已记录 =="
if [ -f "$INFO_PLIST" ] && command -v plutil >/dev/null 2>&1; then
  min_os="$(read_plist "$INFO_PLIST" MinimumOSVersion | tr -d ' "')"
  if [ -n "$min_os" ]; then
    echo "OK: MinimumOSVersion=${min_os}（16.5 SDK 对 iOS 17.0.2 兼容待实测）"
    record_check "d6" "minimum OS version recorded" "passed"
  else
    echo "FAIL: 未记录 MinimumOSVersion"
    record_check "d6" "minimum OS version recorded" "failed"
  fi
else
  echo "unavailable: 缺少 Info.plist 或 plutil"
  record_check "d6" "minimum OS version recorded" "unavailable"
fi

# JSON 摘要
json_checks="["
for i in "${!check_ids[@]}"; do
  [ "$i" -gt 0 ] && json_checks+=","
  json_checks+="{\"id\":\"${check_ids[$i]}\",\"name\":\"${check_names[$i]}\",\"status\":\"${check_status[$i]}\"}"
done
json_checks+="]"
summary="{\"checks\":${json_checks},\"failed\":${fail},\"validator\":\"validate-device-build\"}"

echo "--- summary ---"
echo "$summary"
if [ -n "$SUMMARY_PATH" ]; then
  mkdir -p "$(dirname "$SUMMARY_PATH")"
  echo "$summary" > "$SUMMARY_PATH"
fi

exit "$fail"
