#!/usr/bin/env bash
# Build a RootHide rootfs-layout DEB (not a Rootless conversion package).
# The Debian architecture label is iphoneos-arm64e; the app Mach-O must contain
# at least arm64. These are deliberately validated as separate properties.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENVIRONMENT="${1:?Usage: package-deb.sh <RootHide> <FilterKit.app> <output-directory>}"
APP="${2:?Usage: package-deb.sh <RootHide> <FilterKit.app> <output-directory>}"
OUT="${3:?Usage: package-deb.sh <RootHide> <FilterKit.app> <output-directory>}"

if [[ "$ENVIRONMENT" != "RootHide" ]]; then
  echo "ERROR: This release package script only creates the RootHide rootfs package." >&2
  exit 40
fi

# Package identity and layout live in the external RootHide profile so the
# script only assembles and validates the package. Rootless packaging is not
# produced here; keep that boundary explicit.
PROFILE_ENV="$ROOT/Build/Config/DEB/roothide.env"
[[ -f "$PROFILE_ENV" ]] || { echo "ERROR: RootHide DEB profile missing: $PROFILE_ENV" >&2; exit 40; }
# shellcheck disable=SC1090
source "$PROFILE_ENV"
for required in DEB_PACKAGE_ID DEB_PACKAGE_ARCH DEB_PAYLOAD_RELATIVE_PATH DEB_PAYLOAD_BUNDLE_NAME DEB_REGISTER_PATH DEB_DEPENDS DEB_MAINTAINER DEB_SECTION DEB_PRIORITY DEB_DESCRIPTION; do
  [[ -n "${!required:-}" ]] || { echo "ERROR: profile variable $required is empty in $PROFILE_ENV" >&2; exit 40; }
done
[[ "$DEB_PAYLOAD_RELATIVE_PATH" == */"$DEB_PAYLOAD_BUNDLE_NAME" ]] \
  || { echo "ERROR: payload path '$DEB_PAYLOAD_RELATIVE_PATH' does not end in bundle '$DEB_PAYLOAD_BUNDLE_NAME'" >&2; exit 40; }
[[ "$DEB_REGISTER_PATH" == "/$DEB_PAYLOAD_RELATIVE_PATH" ]] \
  || { echo "ERROR: register path '$DEB_REGISTER_PATH' must be rootfs path '/$DEB_PAYLOAD_RELATIVE_PATH'" >&2; exit 40; }

[[ -d "$APP" && -f "$APP/Info.plist" ]] || { echo "ERROR: FilterKit.app or Info.plist missing: $APP" >&2; exit 41; }
command -v dpkg-deb >/dev/null 2>&1 || { echo "ERROR: dpkg-deb is required." >&2; exit 42; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 43; }

META="$(python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    d = plistlib.load(f)
for k in ('CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion','CFBundleExecutable'):
    v=d.get(k,'')
    print(v if isinstance(v,str) else '')
PY
)"
BUNDLE_ID="$(printf '%s\n' "$META" | sed -n '1p')"
APP_VERSION="$(printf '%s\n' "$META" | sed -n '2p')"
BUILD_VERSION="$(printf '%s\n' "$META" | sed -n '3p')"
EXECUTABLE="$(printf '%s\n' "$META" | sed -n '4p')"
[[ "$BUNDLE_ID" == "cn.yfen.filterkit" ]] || { echo "ERROR: unexpected bundle id: $BUNDLE_ID" >&2; exit 44; }
[[ -n "$APP_VERSION" && "$APP_VERSION" =~ ^[0-9A-Za-z.+:~_-]+$ ]] || { echo "ERROR: invalid/missing marketing version: $APP_VERSION" >&2; exit 45; }
[[ -n "$BUILD_VERSION" ]] || { echo "ERROR: CFBundleVersion is missing." >&2; exit 46; }
[[ -n "$EXECUTABLE" && "$EXECUTABLE" != */* && "$EXECUTABLE" != "." && "$EXECUTABLE" != ".." && -f "$APP/$EXECUTABLE" ]] || { echo "ERROR: CFBundleExecutable missing or invalid: $EXECUTABLE" >&2; exit 47; }
[[ -x "$APP/$EXECUTABLE" ]] || { echo "ERROR: main executable is not executable: $APP/$EXECUTABLE" >&2; exit 48; }

# RootHide's package-manager architecture is not the app's Mach-O slice.
# Values come from the external roothide.env profile; the Mach-O slice is
# validated independently below.
PACKAGE_ARCH="$DEB_PACKAGE_ARCH"
DEB_VERSION="${APP_VERSION}-1"
PACKAGE_ID="$DEB_PACKAGE_ID"
[[ "$PACKAGE_ID" == "$BUNDLE_ID" ]] || { echo "ERROR: profile package id '$PACKAGE_ID' does not match App bundle id '$BUNDLE_ID'" >&2; exit 44; }
if command -v lipo >/dev/null 2>&1; then
  APP_ARCHS="$(lipo -archs "$APP/$EXECUTABLE" 2>/dev/null || true)"
  [[ " $APP_ARCHS " == *" arm64 "* || " $APP_ARCHS " == *" arm64e "* ]] || {
    echo "ERROR: app executable must contain arm64 or arm64e; found: ${APP_ARCHS:-unknown}" >&2; exit 49;
  }
else
  echo "ERROR: lipo is required to verify the app Mach-O architecture." >&2; exit 50
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/filterkit-roothide-deb.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/package"
PAYLOAD="$STAGE/$DEB_PAYLOAD_RELATIVE_PATH"
mkdir -p "$PAYLOAD" "$STAGE/DEBIAN"
if command -v ditto >/dev/null 2>&1; then ditto "$APP" "$PAYLOAD"; else cp -R "$APP/." "$PAYLOAD/"; fi

SIGNATURE_STATE="unsigned-structure"
if [[ "${ALLOW_UNSIGNED_STRUCTURE_PACKAGE:-0}" == "1" ]]; then
  echo "WARNING: building an explicitly non-installable unsigned structure fixture." >&2
  [[ "${OUT##*.}" == "deb" ]] || true
else
  command -v ldid >/dev/null 2>&1 || { echo "ERROR: ldid is required for RootHide DEB signing; refusing to emit unsigned package." >&2; exit 51; }
  command -v otool >/dev/null 2>&1 || { echo "ERROR: otool is required for signature verification." >&2; exit 52; }
  command -v file >/dev/null 2>&1 || { echo "ERROR: file is required for Mach-O enumeration." >&2; exit 53; }
  ENTITLEMENTS="$ROOT/Build/Signing/FilterKit.entitlements"
  [[ -f "$ENTITLEMENTS" ]] || { echo "ERROR: RootHide signing entitlements missing: $ENTITLEMENTS" >&2; exit 54; }
  APP_PATH="$PAYLOAD" ENTITLEMENTS_PATH="$ENTITLEMENTS" \
    bash "$ROOT/Build/Scripts/sign-app-ldid.sh" sign "$PAYLOAD"
  APP_PATH="$PAYLOAD" ENTITLEMENTS_PATH="$ENTITLEMENTS" \
    bash "$ROOT/Build/Scripts/sign-app-ldid.sh" verify "$PAYLOAD"
  SIGNATURE_STATE="ldid-signed-static-valid"
fi

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: $PACKAGE_ID
Name: FilterKit
Version: $DEB_VERSION
Architecture: $PACKAGE_ARCH
Maintainer: $DEB_MAINTAINER
Section: $DEB_SECTION
Priority: $DEB_PRIORITY
Depends: $DEB_DEPENDS
Description: $DEB_DESCRIPTION
CONTROL

cat > "$STAGE/DEBIAN/postinst" <<POSTINST
#!/bin/sh
# RootHide rootfs-layout registration only. No plugin or ElleKit configuration writes.
if [ "\$1" = "configure" ]; then
    if command -v uicache >/dev/null 2>&1; then
        uicache -p "$DEB_REGISTER_PATH" >/dev/null 2>&1 || true
    elif [ -x /usr/bin/uicache ]; then
        /usr/bin/uicache -p "$DEB_REGISTER_PATH" >/dev/null 2>&1 || true
    fi
fi
exit 0
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"

if ! dpkg-deb --help 2>&1 | grep -q -- '--root-owner-group'; then
  echo "ERROR: dpkg-deb with --root-owner-group is required." >&2; exit 55
fi
mkdir -p "$OUT"
SUFFIX=""
if [[ "$SIGNATURE_STATE" == "unsigned-structure" ]]; then SUFFIX=".unsigned-structure"; fi
DEST="$OUT/${PACKAGE_ID}_${DEB_VERSION}_${PACKAGE_ARCH}${SUFFIX}.deb"
rm -f "$DEST"
dpkg-deb --build --root-owner-group "$STAGE" "$DEST" >/dev/null

# Validate exact package identity, RootHide rootfs payload (no /var/jb prefix),
# maintainer script, and signatures again after archive extraction.
dpkg-deb --info "$DEST" >/dev/null
[[ "$(dpkg-deb --field "$DEST" Package)" == "$PACKAGE_ID" ]]
[[ "$(dpkg-deb --field "$DEST" Version)" == "$DEB_VERSION" ]]
[[ "$(dpkg-deb --field "$DEST" Architecture)" == "$PACKAGE_ARCH" ]]
dpkg-deb --contents "$DEST" | grep -F "$DEB_PAYLOAD_RELATIVE_PATH/Info.plist" >/dev/null
if dpkg-deb --contents "$DEST" | grep -F 'var/jb/Applications/FilterKit.app' >/dev/null; then
  echo "ERROR: RootHide package unexpectedly contains a Rootless /var/jb payload prefix." >&2; rm -f "$DEST"; exit 56
fi
POSTINST_EXTRACT="$WORK/postinst"
dpkg-deb --ctrl-tarfile "$DEST" | tar -xOf - ./postinst > "$POSTINST_EXTRACT"
sh -n "$POSTINST_EXTRACT"
if [[ "$SIGNATURE_STATE" == "ldid-signed-static-valid" ]]; then
  EXTRACT="$WORK/extracted"
  mkdir -p "$EXTRACT"
  dpkg-deb --extract "$DEST" "$EXTRACT"
  APP_PATH="$EXTRACT/$DEB_PAYLOAD_RELATIVE_PATH" ENTITLEMENTS_PATH="$ROOT/Build/Signing/FilterKit.entitlements" \
    bash "$ROOT/Build/Scripts/sign-app-ldid.sh" verify "$EXTRACT/$DEB_PAYLOAD_RELATIVE_PATH"
fi

printf 'DEB_CREATED=%s\n' "$DEST"
printf 'DEB_PROFILE=%s\n' "$DEB_PROFILE_ID"
printf 'DEB_PACKAGE_ARCH=%s\n' "$PACKAGE_ARCH"
printf 'DEB_PAYLOAD=%s\n' "$DEB_PAYLOAD_RELATIVE_PATH"
printf 'APP_MACHO_ARCH=%s\n' "$APP_ARCHS"
printf 'APP_VERSION=%s\nAPP_BUILD=%s\n' "$APP_VERSION" "$BUILD_VERSION"
printf 'DEB_SIGNATURE_STATE=%s\n' "$SIGNATURE_STATE"
printf 'DEB_DEVICE_ACCEPTANCE=pending-real-device-install-launch-test\n'
if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$DEST"; fi
