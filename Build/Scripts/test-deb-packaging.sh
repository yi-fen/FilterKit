#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for tool in dpkg-deb ldid lipo clang file otool python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: required macOS packaging tool missing: $tool" >&2; exit 77; }
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
        'CFBundleVersion': 'P1-47.3-PACKAGING-TEST',
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
DEB="$OUT/cn.yfen.filterkit_1.0.0-1_iphoneos-arm64e.deb"
test -s "$DEB"
test "$(dpkg-deb --field "$DEB" Package)" = "cn.yfen.filterkit"
test "$(dpkg-deb --field "$DEB" Version)" = "1.0.0-1"
test "$(dpkg-deb --field "$DEB" Architecture)" = "iphoneos-arm64e"
dpkg-deb --contents "$DEB" | grep -F 'Applications/FilterKit.app/Info.plist' >/dev/null
if dpkg-deb --contents "$DEB" | grep -F 'var/jb/Applications/FilterKit.app' >/dev/null; then
  echo "ERROR: RootHide DEB contains a Rootless /var/jb payload." >&2; exit 1
fi
dpkg-deb --ctrl-tarfile "$DEB" | tar -tf - | grep -Fx './postinst' >/dev/null
mkdir -p "$TMP/extracted"
dpkg-deb --extract "$DEB" "$TMP/extracted"
APP_PATH="$TMP/extracted/Applications/FilterKit.app" \
ENTITLEMENTS_PATH="$ROOT/Build/Signing/FilterKit.entitlements" \
  bash "$ROOT/Build/Scripts/sign-app-ldid.sh" verify "$TMP/extracted/Applications/FilterKit.app"
echo "PASS: RootHide DEB metadata, rootfs layout, postinst, Mach-O signature and embedded entitlements verified."
echo "DEVICE_ACCEPTANCE=pending-real-device-install-and-launch"
