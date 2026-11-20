#!/usr/bin/env bash
# Sign/inspect a RootHide test App with ldid. This creates a signed candidate only;
# it cannot prove Bootstrap/amfid acceptance, runtime sandbox permissions, or launch.
#
# Sign flow (aligned to the FilterKit-DevDocs-0.1-LDID-Signing-Fix baseline):
#   * every nested Mach-O image is signed ad-hoc WITHOUT the main App entitlements;
#   * only the main CFBundleExecutable receives the reviewed entitlement plist;
#   * signing is immediately followed by scripts/validate-ldid-signature.sh, which
#     checks LC_CODE_SIGNATURE and CDHash extraction on every Mach-O and verifies
#     the main executable's embedded entitlements match the source plist exactly.
#
# Verify flow delegates to the same standalone validator. This script never
# installs, launches, or communicates with a helper/daemon.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-sign}"
APP_PATH="${APP_PATH:-${2:-}}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-Config/Signing/FilterKit.entitlements}"
LDID_BIN="${LDID_BIN:-$(command -v ldid || true)}"
SUMMARY_PATH="${SIGNING_SUMMARY_PATH:-}"

fail() { echo "::error::$*" >&2; exit 1; }
[[ "$MODE" == sign || "$MODE" == verify ]] || fail "Usage: $0 [sign|verify] <FilterKit.app>"
[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "APP_PATH must point to FilterKit.app"
[[ -f "$APP_PATH/Info.plist" ]] || fail "Info.plist missing"
[[ -f "$ENTITLEMENTS_PATH" ]] || fail "Entitlements file missing: $ENTITLEMENTS_PATH"
[[ -n "$LDID_BIN" && -x "$LDID_BIN" ]] || fail "ldid executable not found; refusing unsigned fallback"
for tool in python3 file otool; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool unavailable: $tool"
done

EXECUTABLE="$(python3 - "$APP_PATH/Info.plist" <<'PYINFO'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    v = plistlib.load(f).get('CFBundleExecutable', '')
if not isinstance(v, str) or not v or '/' in v or v in ('.', '..'):
    raise SystemExit('invalid CFBundleExecutable')
print(v)
PYINFO
)"
MAIN_BIN="$APP_PATH/$EXECUTABLE"
[[ -f "$MAIN_BIN" ]] || fail "CFBundleExecutable missing: $MAIN_BIN"

MACHOS=()
while IFS= read -r f; do
  [[ -n "$f" ]] && MACHOS+=("$f")
done < <(find "$APP_PATH" -type f -print0 | while IFS= read -r -d '' f; do
  if file -b "$f" 2>/dev/null | grep -q 'Mach-O'; then printf '%s\n' "$f"; fi
done)
[[ ${#MACHOS[@]} -gt 0 ]] || fail "No Mach-O payload found in App bundle"

run_validator() {
  # Standalone static validator: LC_CODE_SIGNATURE + CDHash on every Mach-O,
  # exact embedded-entitlement match on the main executable only.
  local validator="scripts/validate-ldid-signature.sh"
  [[ -f "$validator" ]] || fail "Validator script missing: $validator"
  LDID_SIGNATURE_SUMMARY_PATH="${SUMMARY_PATH}" \
    bash "$validator" "$APP_PATH"
}

if [[ "$MODE" == sign ]]; then
  [[ -x "$MAIN_BIN" ]] || fail "CFBundleExecutable missing or not executable: $MAIN_BIN"

  echo "Signing $(( ${#MACHOS[@]} - 1 )) nested Mach-O image(s) ad-hoc (no App entitlements)"
  for binary in "${MACHOS[@]}"; do
    [[ "$binary" == "$MAIN_BIN" ]] && continue
    echo "ldid -S ${binary#$APP_PATH/}"
    "$LDID_BIN" -S "$binary"
  done

  echo "Signing main executable with $ENTITLEMENTS_PATH"
  "$LDID_BIN" "-S$ENTITLEMENTS_PATH" "$MAIN_BIN"

  run_validator

  echo "SIGNING_RESULT=ldid_signed_static_valid"
  echo "DEVICE_ACCEPTANCE=unknown DEVICE_INSTALLABLE=false"
else
  # verify: static signature/entitlement state only; device acceptance stays unknown.
  run_validator
fi
