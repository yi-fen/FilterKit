#!/usr/bin/env bash
#
# validate-entitlements.sh — R4-E entitlement 配置静态校验（离线/CI 可执行，不触真机）
#
# 校验目标：entitlements 草稿可解析；四枚候选键是否齐全；是否出现候选清单之外的私有键。
# 本脚本只核对签名声明层内容，不证明签名被接受、不证明运行时放行；
# entitlement 出现在签名中 ≠ 系统授予对应权限。
#
# 用法：bash scripts/validate-entitlements.sh [entitlements.plist]
# 输出：原始文本 + JSON 摘要（PACKAGE_VALIDATION_SUMMARY_PATH 可指定摘要路径）。

set -u
cd "$(dirname "$0")/.."

ENT_PATH="${1:-Config/Signing/FilterKit.entitlements}"
SUMMARY_PATH="${PACKAGE_VALIDATION_SUMMARY_PATH:-}"

fail=0
check_ids=()
check_names=()
check_status=()

record_check() {
  local id="$1" name="$2" status="$3"
  check_ids+=("$id"); check_names+=("$name"); check_status+=("$status")
  [ "$status" = "failed" ] && fail=1
}

# 批准候选清单（与 R4-B 规格一致；新增候选须先过规格冻结）
candidates=(
  "platform-application"
  "com.apple.private.security.no-sandbox"
  "com.apple.private.security.storage.AppBundles"
  "com.apple.private.security.storage.AppDataContainers"
)

# t1. plist 可解析
echo "== t1. entitlements plist 可解析 =="
if [ ! -f "$ENT_PATH" ]; then
  echo "FAIL: 文件缺失：$ENT_PATH"
  record_check "t1" "entitlements plist parseable" "failed"
elif command -v plutil >/dev/null 2>&1; then
  if plutil -lint "$ENT_PATH" >/dev/null 2>&1; then
    echo "OK: plutil -lint 通过"
    record_check "t1" "entitlements plist parseable" "passed"
  else
    echo "FAIL: plist 解析失败"
    record_check "t1" "entitlements plist parseable" "failed"
  fi
else
  echo "unavailable: 无 plutil，跳过解析校验"
  record_check "t1" "entitlements plist parseable" "unavailable"
fi

# 提取 <key> 列表（xml1 转换后 grep）
keys=()
if [ -f "$ENT_PATH" ] && command -v plutil >/dev/null 2>&1; then
  keys=($(plutil -convert xml1 -o - "$ENT_PATH" 2>/dev/null \
    | grep -oE '<key>[^<]+</key>' | sed -E 's#</?key>##g'))
fi

# t2. 四枚候选键是否齐全（无 plutil 时无法提取键名，记 unavailable，不计 failed）
echo "== t2. 候选 entitlement 齐全 =="
if [ "${#keys[@]}" -eq 0 ]; then
  echo "unavailable: 无 plutil 或键列表为空，候选齐全性无法判定"
  record_check "t2" "candidate entitlements present" "unavailable"
else
  missing=()
  for cand in "${candidates[@]}"; do
    present="no"
    for k in "${keys[@]}"; do [ "$k" = "$cand" ] && present="yes"; done
    if [ "$present" = "yes" ]; then
      echo "OK: $cand"
    else
      echo "MISSING: $cand"
      missing+=("$cand")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    record_check "t2" "candidate entitlements present" "passed"
  else
    record_check "t2" "candidate entitlements present" "failed"
  fi
fi

# t3. 无候选清单之外的私有键
echo "== t3. 无未批准私有键 =="
if [ "${#keys[@]}" -eq 0 ]; then
  echo "unavailable: 无 plutil 或键列表为空，未批准键扫描无法判定"
  record_check "t3" "no unapproved entitlement keys" "unavailable"
else
  unknown=()
  for k in "${keys[@]}"; do
    known="no"
    for cand in "${candidates[@]}"; do [ "$k" = "$cand" ] && known="yes"; done
    [ "$known" = "no" ] && unknown+=("$k")
  done
  if [ "${#unknown[@]}" -eq 0 ]; then
    echo "OK: 全部键均在批准候选清单内"
    record_check "t3" "no unapproved entitlement keys" "passed"
  else
    echo "FAIL: 未批准键：${unknown[*]}"
    record_check "t3" "no unapproved entitlement keys" "failed"
  fi
fi

# t4. Current signing plist must remain identical to the archived 0.1.18 reference.
echo "== t4. 与 reference/0.1.18-src/entitlements.plist 完全一致 =="
REFERENCE_ENT_PATH="reference/0.1.18-src/entitlements.plist"
if [ ! -f "$ENT_PATH" ] || [ ! -f "$REFERENCE_ENT_PATH" ] || ! command -v python3 >/dev/null 2>&1; then
  echo "unavailable: 当前 entitlements / 0.1.18 reference / python3 缺失，无法比较"
  record_check "t4" "matches 0.1.18 reference entitlements" "unavailable"
else
  if python3 - "$ENT_PATH" "$REFERENCE_ENT_PATH" <<'PYREF'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    current = plistlib.load(f)
with open(sys.argv[2], 'rb') as f:
    reference = plistlib.load(f)
if current != reference:
    print('FAIL: current entitlement plist differs from reference/0.1.18-src/entitlements.plist')
    raise SystemExit(1)
print('OK: current entitlement plist exactly matches 0.1.18 reference')
PYREF
  then
    record_check "t4" "matches 0.1.18 reference entitlements" "passed"
  else
    record_check "t4" "matches 0.1.18 reference entitlements" "failed"
  fi
fi

json_checks="["
for i in "${!check_ids[@]}"; do
  [ "$i" -gt 0 ] && json_checks+=","
  json_checks+="{\"id\":\"${check_ids[$i]}\",\"name\":\"${check_names[$i]}\",\"status\":\"${check_status[$i]}\"}"
done
json_checks+="]"
summary="{\"checks\":${json_checks},\"failed\":${fail},\"validator\":\"validate-entitlements\"}"

echo "--- summary ---"
echo "$summary"
if [ -n "$SUMMARY_PATH" ]; then
  mkdir -p "$(dirname "$SUMMARY_PATH")"
  echo "$summary" > "$SUMMARY_PATH"
fi

exit "$fail"
