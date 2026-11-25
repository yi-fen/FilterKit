#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for tool in dpkg-deb codesign lipo clang; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool is unavailable; run this test on a macOS Xcode runner." >&2
    exit 77
  fi
done
TMP="$(mktemp -d "${TMPDIR:-/tmp}/filterkit-deb-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/FilterKit.app"
OUT="$TMP/out"
mkdir -p "$APP" "$OUT"
python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleIdentifier': 'cn.yfen.filterkit',
        'CFBundleShortVersionString': '1.0.0',
        'CFBundleVersion': '1',
        'CFBundleExecutable': 'FilterKit',
        'CFBundlePackageType': 'APPL',
    }, f)
PY
cat > "$TMP/stub.c" <<'C'
int main(void) { return 0; }
C
clang -arch arm64 "$TMP/stub.c" -o "$APP/FilterKit"
chmod 755 "$APP/FilterKit"
bash "$ROOT/Build/Scripts/package-deb.sh" RootHide "$APP" "$OUT"
DEB="$OUT/cn.yfen.filterkit_1.0.0-1_iphoneos-arm64.deb"
test -f "$DEB"
test "$(dpkg-deb --field "$DEB" Package)" = "cn.yfen.filterkit"
test "$(dpkg-deb --field "$DEB" Version)" = "1.0.0-1"
test "$(dpkg-deb --field "$DEB" Architecture)" = "iphoneos-arm64"
dpkg-deb --contents "$DEB" | grep -F 'Applications/FilterKit.app/Info.plist' >/dev/null
dpkg-deb --ctrl-tarfile "$DEB" | tar -tf - | grep -Fx './postinst' >/dev/null
mkdir -p "$TMP/extracted"
dpkg-deb --extract "$DEB" "$TMP/extracted"
codesign --verify --deep --strict "$TMP/extracted/Applications/FilterKit.app"
lipo -archs "$TMP/extracted/Applications/FilterKit.app/FilterKit" | grep -qw arm64
if bash "$ROOT/Build/Scripts/package-deb.sh" Rootless "$APP" "$OUT" >/dev/null 2>&1; then
  echo "ERROR: unverified Rootless packaging unexpectedly succeeded." >&2
  exit 1
fi
echo "PASS: RootHide DEB contains an arm64 app with a verified ad-hoc signature and postinst; Rootless correctly rejected."
