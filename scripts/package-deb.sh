#!/usr/bin/env bash
# Build the default RootHide-layout DEB package. Packaging is offline only.
# The package Architecture field (iphoneos-arm64e) is package-manager metadata;
# the Mach-O slice is validated separately and is not forced to arm64e.

set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE_ID="${DEB_PROFILE_ID:-roothide-rootfs}"
PROFILE_FILE="Config/DEB/roothide.env"
CONTROL_SOURCE="Config/DEB/control"
POSTINST_SOURCE="Config/DEB/postinst"
APP_PATH="${APP_PATH:-${1:-}}"
CONTROL_VERSION="$(awk -F': *' '$1 == "Version" {print $2; exit}' "$CONTROL_SOURCE" | tr -d '\r')"
# Device CI currently builds with CODE_SIGNING_ALLOWED=NO. An unsigned package
# is permitted only as an explicitly named static-structure artifact; it must
# never be mistaken for an installable RootHide package.
ALLOW_UNSIGNED_STRUCTURE_PACKAGE="${ALLOW_UNSIGNED_STRUCTURE_PACKAGE:-0}"
OUT_DEB="${OUT_DEB:-}"

if [[ "$PROFILE_ID" != "roothide-rootfs" ]]; then
  echo "::error::Unsupported DEB_PROFILE_ID=$PROFILE_ID; only roothide-rootfs is configured."
  exit 1
fi
if [[ ! -f "$PROFILE_FILE" || ! -f "$CONTROL_SOURCE" || ! -f "$POSTINST_SOURCE" ]]; then
  echo "::error::Missing RootHide DEB profile/control/postinst source."
  exit 1
fi
# shellcheck disable=SC1090
source "$PROFILE_FILE"
if [[ "$DEB_PROFILE_ID" != "$PROFILE_ID" ]]; then
  echo "::error::Profile ID mismatch: requested=$PROFILE_ID configured=$DEB_PROFILE_ID"
  exit 1
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "::error::APP_PATH missing or not a directory: ${APP_PATH:-<empty>}"
  exit 1
fi
if [[ ! -f "$APP_PATH/Info.plist" ]]; then
  echo "::error::App bundle is missing Info.plist: $APP_PATH"
  exit 1
fi
if [[ "$ALLOW_UNSIGNED_STRUCTURE_PACKAGE" != "0" && "$ALLOW_UNSIGNED_STRUCTURE_PACKAGE" != "1" ]]; then
  echo "::error::ALLOW_UNSIGNED_STRUCTURE_PACKAGE must be 0 or 1"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "::error::python3 is required for bundle metadata validation."
  exit 1
fi
APP_EXECUTABLE="$(python3 - "$APP_PATH/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    value = plistlib.load(f).get('CFBundleExecutable', '')
if isinstance(value, str):
    print(value)
PY
)"
APP_BUNDLE_ID="$(python3 - "$APP_PATH/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    print(plistlib.load(f).get('CFBundleIdentifier', ''))
PY
)"
APP_SHORT_VERSION="$(python3 - "$APP_PATH/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    print(plistlib.load(f).get('CFBundleShortVersionString', ''))
PY
)"
APP_VERSION="$(python3 - "$APP_PATH/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    print(plistlib.load(f).get('CFBundleVersion', ''))
PY
)"
CONTROL_PACKAGE="$(awk -F': *' '$1 == "Package" {print $2; exit}' "$CONTROL_SOURCE" | tr -d '\r')"
CONTROL_VERSION_BASE="$(printf '%s' "$CONTROL_VERSION" | sed -E 's/-[0-9]+$//')"
# 预检即打印两侧实际值：App 营销版本/构建号与 control 版本基线，便于在失败日志中直接核对漂移。
echo "App bundle: $APP_BUNDLE_ID; App version=${APP_SHORT_VERSION:-<empty>} build=${APP_VERSION:-<empty>}; control Package=$CONTROL_PACKAGE Version=$CONTROL_VERSION (base=$CONTROL_VERSION_BASE)"
if [[ -z "$APP_EXECUTABLE" || "$APP_EXECUTABLE" == */* || "$APP_EXECUTABLE" == "." || "$APP_EXECUTABLE" == ".." || ! -f "$APP_PATH/$APP_EXECUTABLE" ]]; then
  echo "::error::CFBundleExecutable is missing or does not exist: ${APP_EXECUTABLE:-<empty>}"
  exit 1
fi
if [[ ! -x "$APP_PATH/$APP_EXECUTABLE" ]]; then
  echo "::error::CFBundleExecutable is not executable: $APP_PATH/$APP_EXECUTABLE"
  exit 1
fi
if [[ "$APP_BUNDLE_ID" != "$CONTROL_PACKAGE" ]]; then
  echo "::error::Bundle ID=$APP_BUNDLE_ID does not match control Package=$CONTROL_PACKAGE"
  exit 1
fi
if [[ -z "$APP_SHORT_VERSION" || "$APP_SHORT_VERSION" != "$CONTROL_VERSION_BASE" ]]; then
  echo "::error::App version=${APP_SHORT_VERSION:-<empty>} (build=${APP_VERSION:-<empty>}) does not match control Version base=$CONTROL_VERSION_BASE (control Version=$CONTROL_VERSION)"
  exit 1
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "::error::dpkg-deb is required; no partial/staging-only success is allowed."
  exit 1
fi
if ! dpkg-deb --help 2>&1 | grep -q -- '--root-owner-group'; then
  echo "::error::dpkg-deb lacks --root-owner-group; refusing non-deterministic ownership."
  exit 1
fi

SIGNATURE_STATE="unsigned"
# Detect the explicit RootHide ldid route first; do not relabel it as an Apple-signed app.
if command -v ldid >/dev/null 2>&1 \
    && APP_PATH="$APP_PATH" ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-Config/Signing/FilterKit.entitlements}" \
       bash scripts/sign-app-ldid.sh verify "$APP_PATH" >/dev/null 2>&1; then
  SIGNATURE_STATE="ldid_signed_embedded"
elif command -v codesign >/dev/null 2>&1; then
  if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    SIGNATURE_STATE="signed_valid"
  elif codesign -dv "$APP_PATH" >/dev/null 2>&1; then
    echo "::error::App signature exists but codesign verification failed."
    exit 1
  fi
fi
if [[ "$SIGNATURE_STATE" == "unsigned" && "$ALLOW_UNSIGNED_STRUCTURE_PACKAGE" != "1" ]]; then
  echo "::error::Refusing to produce a signed-candidate-looking DEB from an unsigned App."
  echo "::error::Run scripts/sign-app-ldid.sh sign <FilterKit.app> with the approved RootHide ldid route, or explicitly allow an unsigned structure artifact for static CI only."
  exit 1
fi
if [[ -z "$OUT_DEB" ]]; then
  if [[ "$SIGNATURE_STATE" == "unsigned" ]]; then
    OUT_DEB="build/deb/filterkit_${CONTROL_VERSION}_iphoneos-arm64e.unsigned-structure.deb"
  elif [[ "$SIGNATURE_STATE" == "ldid_signed_embedded" ]]; then
    OUT_DEB="build/deb/filterkit_${CONTROL_VERSION}_iphoneos-arm64e.ldid-signed-candidate.deb"
  else
    OUT_DEB="build/deb/filterkit_${CONTROL_VERSION}_iphoneos-arm64e.apple-signed-candidate.deb"
  fi
fi
if [[ "$SIGNATURE_STATE" == "unsigned" && "$OUT_DEB" != *".unsigned-structure.deb" ]]; then
  echo "::error::Unsigned structure package filename must end with .unsigned-structure.deb"
  exit 1
fi
if [[ "$SIGNATURE_STATE" == "ldid_signed_embedded" && "$OUT_DEB" != *".ldid-signed-candidate.deb" ]]; then
  echo "::error::ldid signed candidate filename must end with .ldid-signed-candidate.deb"
  exit 1
fi
# Remove any previous artifact only after the final signature-aware path is known.
mkdir -p "$(dirname "$OUT_DEB")"
rm -f "$OUT_DEB"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
STAGE="$WORKDIR/Package"
mkdir -p "$STAGE/Applications" "$STAGE/DEBIAN"
# ditto is preferred on macOS because it preserves bundle metadata, symlinks,
# resource forks and extended attributes more faithfully than a generic copy.
if command -v ditto >/dev/null 2>&1; then
  ditto "$APP_PATH" "$STAGE/Applications/FilterKit.app"
else
  cp -R "$APP_PATH" "$STAGE/Applications/FilterKit.app"
fi
cp "$CONTROL_SOURCE" "$STAGE/DEBIAN/control"
cp "$POSTINST_SOURCE" "$STAGE/DEBIAN/postinst"
chmod 755 "$STAGE/DEBIAN/postinst"

# Fail closed if control metadata drifts away from the selected profile.
CONTROL_ARCH="$(awk -F': *' '$1 == "Architecture" {print $2; exit}' "$STAGE/DEBIAN/control" | tr -d '\r')"
if [[ "$CONTROL_ARCH" != "$DEB_PACKAGE_ARCH" ]]; then
  echo "::error::control Architecture=$CONTROL_ARCH, profile requires $DEB_PACKAGE_ARCH"
  exit 1
fi

if ! dpkg-deb --build --root-owner-group "$STAGE" "$OUT_DEB"; then
  rm -f "$OUT_DEB"
  echo "::error::dpkg-deb build failed."
  exit 1
fi
if [[ ! -s "$OUT_DEB" ]] || ! dpkg-deb --info "$OUT_DEB" >/dev/null; then
  rm -f "$OUT_DEB"
  echo "::error::Generated DEB failed immediate archive verification."
  exit 1
fi

printf 'DEB_PROFILE_ID=%s\n' "$PROFILE_ID"
printf 'DEB_PACKAGE_ARCH=%s\n' "$CONTROL_ARCH"
printf 'DEB_PAYLOAD=%s\n' "$DEB_PAYLOAD_RELATIVE_PATH"
printf 'DEB_SHA256='
if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$OUT_DEB" | awk '{print $1}'
elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$OUT_DEB" | awk '{print $1}'
else echo unavailable
fi
printf 'DEB_SIGNATURE_STATE=%s\n' "$SIGNATURE_STATE"
case "$SIGNATURE_STATE" in
  signed_valid) INSTALLABILITY="signed-candidate-not-device-verified" ;;
  ldid_signed_embedded) INSTALLABILITY="device-acceptance-pending" ;;
  *) INSTALLABILITY="not-installable-unsigned-structure" ;;
esac
printf 'DEB_INSTALLABILITY=%s\n' "$INSTALLABILITY"
printf 'DEB_CREATED=%s\n' "$OUT_DEB"
printf '%s\n' 'NOTE: RootHide package layout only; signature verification does not prove amfid acceptance, required entitlements, Bootstrap mapping, installation or launch.'
