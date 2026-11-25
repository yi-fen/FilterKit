#!/usr/bin/env bash
# Validate ldid signatures for every Mach-O in a FilterKit.app bundle.
# This is static evidence only; it does not prove amfid/RootHide acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="${1:-${APP_PATH:-}}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-Config/Signing/FilterKit.entitlements}"
SUMMARY_PATH="${LDID_SIGNATURE_SUMMARY_PATH:-}"

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
[[ -f "$MAIN_EXECUTABLE" ]] || fail "Main executable is missing: $MAIN_EXECUTABLE"

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
[[ "$MAIN_FOUND" -eq 1 ]] || fail "CFBundleExecutable is not recognized as Mach-O: $MAIN_EXECUTABLE"

CHECKED=0
while IFS= read -r -d '' binary; do
  CHECKED=$((CHECKED + 1))
  if ! otool -l "$binary" 2>/dev/null | awk '$1 == "cmd" && $2 == "LC_CODE_SIGNATURE" { found=1 } END { exit !found }'; then
    echo "FAIL: LC_CODE_SIGNATURE missing: $binary"
    exit 1
  fi
  CDHASH_OUTPUT="$WORKDIR/cdhash-$CHECKED.txt"
  if ! ldid -h "$binary" > "$CDHASH_OUTPUT" 2>&1 || [[ ! -s "$CDHASH_OUTPUT" ]]; then
    echo "FAIL: ldid could not read a CodeDirectory hash: $binary"
    cat "$CDHASH_OUTPUT" >&2 2>/dev/null || true
    exit 1
  fi
  echo "OK: LC_CODE_SIGNATURE + ldid CDHash extraction: ${binary#$APP_PATH/}"
  sed 's/^/  CDHash: /' "$CDHASH_OUTPUT"
done < "$MACHO_LIST"

EXTRACTED_ENTITLEMENTS="$WORKDIR/embedded-entitlements.plist"
if ! ldid -e "$MAIN_EXECUTABLE" > "$EXTRACTED_ENTITLEMENTS" 2>"$WORKDIR/ldid-extract.log"; then
  cat "$WORKDIR/ldid-extract.log" >&2 || true
  fail "ldid could not extract entitlements from the main executable"
fi
if [[ ! -s "$EXTRACTED_ENTITLEMENTS" ]]; then
  fail "Main executable contains no extractable entitlements"
fi

python3 - "$ENTITLEMENTS_PATH" "$EXTRACTED_ENTITLEMENTS" <<'PY'
import json, plistlib, sys
source_path, embedded_path = sys.argv[1:]
def load(path):
    with open(path, 'rb') as f:
        return plistlib.load(f)
source = load(source_path)
embedded = load(embedded_path)
if source != embedded:
    print('FAIL: embedded entitlements differ from Config/Signing/FilterKit.entitlements')
    print('Expected:', json.dumps(source, sort_keys=True, ensure_ascii=False))
    print('Actual:  ', json.dumps(embedded, sort_keys=True, ensure_ascii=False))
    raise SystemExit(1)
print('OK: embedded entitlements exactly match source plist')
print('ENTITLEMENT_KEYS=' + ','.join(sorted(source.keys())))
PY

APP_BUNDLE_ID="$(python3 - "$APP_PATH/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    print(plistlib.load(f).get('CFBundleIdentifier', ''))
PY
)"
SUMMARY="$(python3 - "$APP_BUNDLE_ID" "$MACHO_COUNT" <<'PY'
import json, sys
print(json.dumps({
  'validator': 'validate-ldid-signature',
  'signatureState': 'ldid_signed_static_valid',
  'bundleIdentifier': sys.argv[1],
  'machoCount': int(sys.argv[2]),
  'lcCodeSignature': 'present_all_macho',
  'codeDirectoryHash': 'extractable_all_macho',
  'embeddedEntitlements': 'exact_match',
  'deviceAcceptance': 'unknown',
  'deviceInstallable': False
}, sort_keys=True))
PY
)"
echo "--- ldid signature summary ---"
echo "$SUMMARY"
if [[ -n "$SUMMARY_PATH" ]]; then
  mkdir -p "$(dirname "$SUMMARY_PATH")"
  printf '%s\n' "$SUMMARY" > "$SUMMARY_PATH"
fi
