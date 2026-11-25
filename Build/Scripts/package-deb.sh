#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENVIRONMENT="${1:?Usage: package-deb.sh <RootHide|Rootless> <FilterKit.app> <output-directory>}"
APP="${2:?Usage: package-deb.sh <RootHide|Rootless> <FilterKit.app> <output-directory>}"
OUT="${3:?Usage: package-deb.sh <RootHide|Rootless> <FilterKit.app> <output-directory>}"

if [[ "$ENVIRONMENT" != "RootHide" ]]; then
  echo "ERROR: DEB packaging is currently enabled only for the registered RootHide profile. Rootless package layout is not verified." >&2
  exit 40
fi
if [[ ! -d "$APP" || ! -f "$APP/Info.plist" ]]; then
  echo "ERROR: FilterKit.app or its Info.plist is missing: $APP" >&2
  exit 41
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "ERROR: dpkg-deb is required. On GitHub macOS runners install it with: brew install dpkg" >&2
  exit 42
fi
if ! command -v codesign >/dev/null 2>&1 || ! command -v lipo >/dev/null 2>&1; then
  echo "ERROR: Apple's codesign and lipo tools are required to validate and sign the iOS app payload." >&2
  exit 45
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/filterkit-deb.XXXXXX")"
META_FILE="$(mktemp "${TMPDIR:-/tmp}/filterkit-app-meta.XXXXXX")"
trap 'rm -rf "$WORK"; rm -f "$META_FILE"' EXIT
python3 - "$APP/Info.plist" > "$META_FILE" <<'PYMETA'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    info = plistlib.load(f)
for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleExecutable'):
    value = info.get(key, '')
    print(value if isinstance(value, str) else '')
PYMETA
BUNDLE_ID="$(sed -n '1p' "$META_FILE")"
APP_VERSION="$(sed -n '2p' "$META_FILE")"
BUILD_VERSION="$(sed -n '3p' "$META_FILE")"
EXECUTABLE="$(sed -n '4p' "$META_FILE")"

if [[ "$BUNDLE_ID" != "cn.yfen.filterkit" ]]; then
  echo "ERROR: unexpected CFBundleIdentifier '$BUNDLE_ID' (expected cn.yfen.filterkit)." >&2
  exit 43
fi
if [[ -z "$APP_VERSION" || -z "$BUILD_VERSION" || -z "$EXECUTABLE" || ! -f "$APP/$EXECUTABLE" ]]; then
  echo "ERROR: app Info.plist is missing version/build/executable metadata or executable file." >&2
  exit 44
fi

# Debian versions permit the upstream version followed by a packaging revision.
DEB_VERSION="${APP_VERSION}-1"
PACKAGE_NAME="cn.yfen.filterkit"
ARCHITECTURE="iphoneos-arm64"
PKGROOT="$WORK/package"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/FilterKit.app"

# The CI Xcode build is intentionally unsigned. Sign the final packaged app
# bundle ad-hoc after copying it, so Sileo-installed apps do not ship without
# an embedded code signature. No Apple Developer certificate is required.
bash "$ROOT/Build/Scripts/sign-ios-app.sh" "$PKGROOT/Applications/FilterKit.app"

cat > "$PKGROOT/DEBIAN/control" <<CONTROL
Package: $PACKAGE_NAME
Name: FilterKit
Version: $DEB_VERSION
Architecture: $ARCHITECTURE
Description: RootHide and ElleKit plugin manager
Maintainer: FilterKit Project
Section: Applications
Priority: optional
Installed-Size: $(du -sk "$PKGROOT/Applications/FilterKit.app" | awk '{print $1}')
CONTROL

cat > "$PKGROOT/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
# Register the installed application with SpringBoard. Failure to refresh the
# icon cache must never turn a successful dpkg payload installation into an
# installation failure.
APP="/Applications/FilterKit.app"
if [ -d "$APP" ]; then
    if command -v uicache >/dev/null 2>&1; then
        uicache -p "$APP" >/dev/null 2>&1 || true
    elif [ -x /usr/bin/uicache ]; then
        /usr/bin/uicache -p "$APP" >/dev/null 2>&1 || true
    fi
fi
exit 0
POSTINST
chmod 755 "$PKGROOT/DEBIAN/postinst"

# Build, then validate the Debian control metadata and payload.
dpkg-deb --build --root-owner-group "$PKGROOT" "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" >/dev/null

dpkg-deb --field "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" Package | grep -Fx "$PACKAGE_NAME" >/dev/null
dpkg-deb --field "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" Version | grep -Fx "$DEB_VERSION" >/dev/null
dpkg-deb --field "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" Architecture | grep -Fx "$ARCHITECTURE" >/dev/null
dpkg-deb --ctrl-tarfile "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" | tar -tf - | grep -Fx "./postinst" >/dev/null
dpkg-deb --contents "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" | grep -F 'Applications/FilterKit.app/Info.plist' >/dev/null

mkdir -p "$OUT"
DEST="$OUT/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb"
cp "$WORK/${PACKAGE_NAME}_${DEB_VERSION}_${ARCHITECTURE}.deb" "$DEST"

echo "DEB created: $DEST"
echo "Package: $PACKAGE_NAME"
echo "Version: $DEB_VERSION (CFBundleVersion $BUILD_VERSION)"
echo "Architecture: $ARCHITECTURE"
echo "Install path: /Applications/FilterKit.app"
echo "Code signature: ad-hoc (verified)"
echo "App architecture: arm64 (verified)"
