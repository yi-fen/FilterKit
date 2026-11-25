#!/usr/bin/env bash
set -euo pipefail
APP="${1:?Usage: sign-ios-app.sh <FilterKit.app>}"
if [[ ! -d "$APP" || ! -f "$APP/Info.plist" ]]; then
  echo "ERROR: app bundle or Info.plist is missing: $APP" >&2
  exit 50
fi
if ! command -v codesign >/dev/null 2>&1 || ! command -v lipo >/dev/null 2>&1; then
  echo "ERROR: codesign and lipo are required (run this packaging step on macOS with Xcode)." >&2
  exit 51
fi
EXECUTABLE="$(python3 - "$APP/Info.plist" <<'PYMETA'
import plistlib, sys
try:
    with open(sys.argv[1], 'rb') as f:
        value = plistlib.load(f).get('CFBundleExecutable', '')
    print(value if isinstance(value, str) else '')
except Exception:
    print('')
PYMETA
)"
if [[ -z "$EXECUTABLE" || ! -f "$APP/$EXECUTABLE" ]]; then
  echo "ERROR: CFBundleExecutable is missing or does not exist in the app bundle." >&2
  exit 52
fi
ARCHS="$(lipo -archs "$APP/$EXECUTABLE" 2>/dev/null || true)"
if [[ " $ARCHS " != *" arm64 "* ]]; then
  echo "ERROR: FilterKit app executable must contain an arm64 slice; found: ${ARCHS:-unknown}. arm64e-only app builds are not supported." >&2
  exit 53
fi
# Remove any stale signature copied from a prior build, then create a fresh
# ad-hoc signature for the final bundle. --deep signs nested frameworks/code.
codesign --remove-signature "$APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
DETAILS="$(codesign --display --verbose=4 "$APP" 2>&1 || true)"
if ! grep -q 'Signature=adhoc' <<<"$DETAILS"; then
  echo "ERROR: resulting app signature is not ad-hoc signed." >&2
  exit 54
fi
echo "PASS: app bundle is arm64 and has a verified ad-hoc code signature."
