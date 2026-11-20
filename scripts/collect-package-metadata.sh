#!/usr/bin/env bash
#
# collect-package-metadata.sh — R4-E 构建/打包元数据与 SHA256 汇总（离线/CI 可执行，不触真机）
#
# 汇总口径（与 R4 规格 §3.5 / 授权稿 §五一致）：
#   - Build Passed      = 成功生成 iPhoneOS 设备构建产物（静态校验 failed=0）；
#   - IPA Package Passed / DEB RootHide Package Layout Passed (Static) = 对应静态摘要 failed=0；
#   - Device Install Pending = 真机安装/注册/启动成功，属 R4-G 真机门禁，R4-A～E 不取证。
#
# 本脚本只做静态元数据归集与哈希复算，不证明 RootHide 真机权限、真实加载或 jbroot() 可调用。
#
# 输入（环境变量，均可缺省；缺省记 Pending/unavailable）：
#   APP_PATH            设备 FilterKit.app 路径
#   IPA_PATH            IPA 结构包路径
#   DEB_PATH            DEB 测试包路径
#   DEVICE_SUMMARY      validate-device-build.sh 摘要 JSON 路径
#   IPA_SUMMARY         validate-ipa.sh 摘要 JSON 路径
#   DEB_SUMMARY         validate-deb.sh 摘要 JSON 路径
#   ENT_SUMMARY         validate-entitlements.sh 摘要 JSON 路径
#   PACKAGE_METADATA_PATH  输出元数据 JSON 路径（缺省仅打印到 stdout）
#
# 退出码：0 = 元数据已归集；产物缺失记 Pending，不视为失败。

set -u
cd "$(dirname "$0")/.."

APP_PATH="${APP_PATH:-}"
IPA_PATH="${IPA_PATH:-}"
DEB_PATH="${DEB_PATH:-}"
DEVICE_SUMMARY="${DEVICE_SUMMARY:-}"
IPA_SUMMARY="${IPA_SUMMARY:-}"
DEB_SUMMARY="${DEB_SUMMARY:-}"
ENT_SUMMARY="${ENT_SUMMARY:-}"
OUT_METADATA="${PACKAGE_METADATA_PATH:-}"

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

sha256_of() {
  local f="$1"
  if [ ! -f "$f" ]; then echo ""; return; fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    echo ""
  fi
}

# 读取校验摘要的 failed 计数；无摘要/无工具记 unknown
summary_failed() {
  local s="$1"
  if [ -z "$s" ] || [ ! -f "$s" ]; then echo "unknown"; return; fi
  if command -v jq >/dev/null 2>&1; then
    jq -r '.failed // "unknown"' "$s" 2>/dev/null || echo "unknown"
  else
    grep -oE '"failed"[[:space:]]*:[[:space:]]*[0-9]+' "$s" | head -1 | grep -oE '[0-9]+' || echo "unknown"
  fi
}

summary_json_or_null() {
  local s="$1"
  if [ -n "$s" ] && [ -f "$s" ]; then cat "$s"; else echo "null"; fi
}

# ── 设备构建状态 ──────────────────────────────────────────────────────────
DEV_STATUS="Build Pending"
PLATFORM="unavailable"
ARCH="unavailable"
BUNDLE="unavailable"
MIN_OS="unavailable"
BINARY="$APP_PATH/FilterKit"
INFO_PLIST="$APP_PATH/Info.plist"

if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
  if [ -f "$INFO_PLIST" ]; then
    PLATFORM="$(read_plist "$INFO_PLIST" DTPlatformName || true)"; PLATFORM="${PLATFORM:-unavailable}"
    BUNDLE="$(read_plist "$INFO_PLIST" CFBundleIdentifier | tr -d ' "')"; BUNDLE="${BUNDLE:-unavailable}"
    MIN_OS="$(read_plist "$INFO_PLIST" MinimumOSVersion | tr -d ' "')"; MIN_OS="${MIN_OS:-unavailable}"
  fi
  if [ -f "$BINARY" ] && command -v lipo >/dev/null 2>&1; then
    ARCH="$(lipo -info "$BINARY" 2>/dev/null | sed -E 's#^.*are: ##; s#^Architecture: ##')"; ARCH="${ARCH:-unavailable}"
  elif [ -f "$BINARY" ] && command -v file >/dev/null 2>&1; then
    ARCH="$(file -b "$BINARY")"
  fi
  dev_failed="$(summary_failed "$DEVICE_SUMMARY")"
  if [ "$dev_failed" = "0" ]; then
    DEV_STATUS="Build Passed"
  elif [ "$dev_failed" = "unknown" ]; then
    DEV_STATUS="Build Pending"
  else
    DEV_STATUS="Build Failed"
  fi
fi

# ── 包状态 ────────────────────────────────────────────────────────────────
package_status() {
  local artifact="$1" summary="$2"
  if [ -z "$artifact" ] || [ ! -f "$artifact" ]; then echo "Package Pending"; return; fi
  local f; f="$(summary_failed "$summary")"
  if [ "$f" = "0" ]; then echo "Package Passed"
  elif [ "$f" = "unknown" ]; then echo "Package Pending"
  else echo "Package Failed"; fi
}

IPA_STATUS="$(package_status "$IPA_PATH" "$IPA_SUMMARY")"
DEB_STATUS="$(package_status "$DEB_PATH" "$DEB_SUMMARY")"
if [ "$DEB_STATUS" = "Package Passed" ]; then DEB_STATUS="RootHide Package Layout Passed (Static)"; fi
IPA_SHA="$(sha256_of "$IPA_PATH")"; IPA_SHA="${IPA_SHA:-unavailable}"
DEB_SHA="$(sha256_of "$DEB_PATH")"; DEB_SHA="${DEB_SHA:-unavailable}"

summary_field() {
  local summary="$1" field="$2"
  if [ -z "$summary" ] || [ ! -f "$summary" ]; then echo "unavailable"; return; fi
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$field" '.[$key] // "unavailable"' "$summary" 2>/dev/null || echo "unavailable"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$summary" "$field" <<'PYFIELD'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.load(f).get(sys.argv[2], "unavailable"))
except Exception:
    print("unavailable")
PYFIELD
  else echo "unavailable"; fi
}
DEB_PROFILE="$(summary_field "$DEB_SUMMARY" profile)"
DEB_PACKAGE_ARCH="$(summary_field "$DEB_SUMMARY" packageArchitecture)"
DEB_MIN_MACHO_ARCH="$(summary_field "$DEB_SUMMARY" minimumMachOArchitecture)"
DEB_SIGNATURE_STATE="$(summary_field "$DEB_SUMMARY" signatureState)"
DEB_INSTALLABILITY="$(summary_field "$DEB_SUMMARY" installability)"

ENT_STATUS="Entitlements Pending"
ent_failed="$(summary_failed "$ENT_SUMMARY")"
if [ "$ent_failed" = "0" ]; then ENT_STATUS="Entitlements Static Passed"
elif [ "$ent_failed" != "unknown" ]; then ENT_STATUS="Entitlements Static Failed"; fi

COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"
RUNNER_OS_NAME="${RUNNER_OS:-local}"
RUNNER_NAME_VAL="${RUNNER_NAME:-local}"
RUN_ID="${GITHUB_RUN_ID:-local}"
GENERATED_AT="$(date -u +%FT%TZ)"

DEVICE_SUMMARY_JSON="$(summary_json_or_null "$DEVICE_SUMMARY")"
IPA_SUMMARY_JSON="$(summary_json_or_null "$IPA_SUMMARY")"
DEB_SUMMARY_JSON="$(summary_json_or_null "$DEB_SUMMARY")"
ENT_SUMMARY_JSON="$(summary_json_or_null "$ENT_SUMMARY")"

META_JSON="$(cat <<EOF
{
  "stage": "0.1-D-R4",
  "generatedAt": "${GENERATED_AT}",
  "commitSha": "${COMMIT_SHA}",
  "runner": {
    "os": "${RUNNER_OS_NAME}",
    "name": "${RUNNER_NAME_VAL}",
    "runId": "${RUN_ID}"
  },
  "deviceBuild": {
    "appPath": "${APP_PATH:-unavailable}",
    "platform": "${PLATFORM}",
    "architecture": "${ARCH}",
    "bundleId": "${BUNDLE}",
    "minimumOsVersion": "${MIN_OS}",
    "status": "${DEV_STATUS}"
  },
  "packages": {
    "ipa": {
      "path": "${IPA_PATH:-unavailable}",
      "sha256": "${IPA_SHA}",
      "status": "${IPA_STATUS}"
    },
    "deb": {
      "path": "${DEB_PATH:-unavailable}",
      "sha256": "${DEB_SHA}",
      "profile": "${DEB_PROFILE}",
      "packageArchitecture": "${DEB_PACKAGE_ARCH}",
      "minimumMachOArchitecture": "${DEB_MIN_MACHO_ARCH}",
      "signatureState": "${DEB_SIGNATURE_STATE}",
      "installability": "${DEB_INSTALLABILITY}",
      "status": "${DEB_STATUS}"
    }
  },
  "entitlements": {
    "path": "Config/Signing/FilterKit.entitlements",
    "status": "${ENT_STATUS}"
  },
  "deviceInstall": {
    "status": "Device Install Pending",
    "note": "真机安装/注册/启动属 R4-G 门禁，本轮 R4-A～E 未授权、不取证；模拟器产物不得作为设备构建证据。"
  },
  "validation": {
    "deviceBuild": ${DEVICE_SUMMARY_JSON},
    "ipa": ${IPA_SUMMARY_JSON},
    "deb": ${DEB_SUMMARY_JSON},
    "entitlements": ${ENT_SUMMARY_JSON}
  },
  "limitations": [
    "本机/离线 CI 未执行真实设备签名放行验证",
    "未调用 RootHide jbroot() 真机 API",
    "DEB RootHide profile 仅证明 rootfs 相对包布局；RootHide 专用链接/弱链接/rpath、签名放行、JBROOT 映射与 uicache 行为仍待目标环境实测",
    "16.5 SDK 对 iOS 17.0.2 向下兼容待实测",
    "R4-E 通过仅证明包符合部署要求，不代表 RootHide 真机权限通过"
  ]
}
EOF
)"

printf '%s\n' "$META_JSON"
if [ -n "$OUT_METADATA" ]; then
  mkdir -p "$(dirname "$OUT_METADATA")"
  printf '%s\n' "$META_JSON" > "$OUT_METADATA"
fi
