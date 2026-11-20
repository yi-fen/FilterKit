#!/usr/bin/env bash
# Sign a device-built FilterKit.app for the jailbreak candidate route using ldid.
# Nested Mach-O images are signed first; the main app executable receives the
# reviewed entitlement plist. This never installs or launches the app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="${1:-${APP_PATH:-}}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-Config/Signing/FilterKit.entitlements}"
LOG_PREFIX="${LDID_LOG_PREFIX:-[FilterKit ldid]}"

fail() { echo "::error::$*" >&2; exit 1; }
[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "APP_PATH is missing or not a directory: ${APP_PATH:-<empty>}"
[[ -f "$APP_PATH/Info.plist" ]] || fail "App Info.plist is missing: $APP_PATH/Info.plist"
[[ -f "$ENTITLEMENTS_PATH" ]] || fail "Entitlements file is missing: $ENTITLEMENTS_PATH"
for tool in ldid otool file python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool is unavailable: $tool"
done

MAIN_EXECUTABLE_NAME="$(python3 - "$APP_PATH/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    value = plistlib.load(f).get('CFBundleExecutable', '')
if not isinstance(value, str) or not value or '/' in value or value in ('.', '..'):
    raise SystemExit('Invalid CFBundleExecutable')
print(value)
PY
)"
MAIN_EXECUTABLE="$APP_PATH/$MAIN_EXECUTABLE_NAME"
[[ -f "$MAIN_EXECUTABLE" && -x "$MAIN_EXECUTABLE" ]] || fail "Main executable is missing or not executable: $MAIN_EXECUTABLE"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
MACHO_LIST="$WORKDIR/macho-files.nul"
: > "$MACHO_LIST"
while IFS= read -r -d '' candidate; do
  if file -b "$candidate" 2>/dev/null | grep -q 'Mach-O'; then
    printf '%s\0' "$candidate" >> "$MACHO_LIST"
  fi
done < <(find "$APP_PATH" -type f -print0)

MACHO_COUNT=0
MAIN_FOUND=0
while IFS= read -r -d '' binary; do
  MACHO_COUNT=$((MACHO_COUNT + 1))
  [[ "$binary" == "$MAIN_EXECUTABLE" ]] && MAIN_FOUND=1
done < "$MACHO_LIST"
[[ "$MACHO_COUNT" -gt 0 ]] || fail "No Mach-O files found under $APP_PATH"
[[ "$MAIN_FOUND" -eq 1 ]] || fail "CFBundleExecutable is not Mach-O: $MAIN_EXECUTABLE"

echo "$LOG_PREFIX Signing $((MACHO_COUNT - 1)) nested Mach-O image(s) without app entitlements"
while IFS= read -r -d '' binary; do
  [[ "$binary" == "$MAIN_EXECUTABLE" ]] && continue
  echo "$LOG_PREFIX ldid -S ${binary#$APP_PATH/}"
  ldid -S "$binary"
done < "$MACHO_LIST"

echo "$LOG_PREFIX Signing main executable with $ENTITLEMENTS_PATH"
ldid -S"$ENTITLEMENTS_PATH" "$MAIN_EXECUTABLE"

# Validate immediately after signing. The validator checks every LC_CODE_SIGNATURE,
# LC_CODE_SIGNATURE, CodeDirectory hash readability, and exact embedded-entitlement equality.
LDID_SIGNATURE_SUMMARY_PATH="${LDID_SIGNATURE_SUMMARY_PATH:-}" \
  bash scripts/validate-ldid-signature.sh "$APP_PATH"

echo "$LOG_PREFIX SIGNING_RESULT=ldid_signed_static_valid"
echo "$LOG_PREFIX DEVICE_ACCEPTANCE=unknown DEVICE_INSTALLABLE=false"
