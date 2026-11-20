#!/usr/bin/env bash
# Static validation for the default RootHide rootfs-layout DEB. No device access.
set -u
cd "$(dirname "$0")/.."

DEB_PATH="${1:-${DEB_PATH:-}}"
SOURCE_APP_PATH="${SOURCE_APP_PATH:-}"
SUMMARY_PATH="${PACKAGE_VALIDATION_SUMMARY_PATH:-}"
PROFILE_FILE="Config/DEB/roothide.env"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "::error::RootHide DEB profile missing: $PROFILE_FILE"
  exit 1
fi
# shellcheck disable=SC1090
source "$PROFILE_FILE"
fail=0
check_ids=()
check_names=()
check_status=()
record_check() {
  local id="$1" name="$2" status="$3"
  check_ids+=("$id"); check_names+=("$name")
  if [[ "$status" == "unavailable" && "${REQUIRE_DEB_VALIDATION_TOOLS:-0}" == "1" ]]; then
    status="failed"
  fi
  check_status+=("$status")
  [[ "$status" == "failed" ]] && fail=1
}

CONTROL_DIR="$WORKDIR/control"
DATA_DIR="$WORKDIR/data"
mkdir -p "$CONTROL_DIR" "$DATA_DIR"
CONTROL_FILE="$CONTROL_DIR/control"
POSTINST_FILE="$CONTROL_DIR/postinst"
APP_DIR="$DATA_DIR/Applications/FilterKit.app"

# e1: archive integrity and extractability
printf '%s\n' '== e1. DEB archive readable and extractable =='
if [[ -n "$DEB_PATH" && -f "$DEB_PATH" ]] && command -v dpkg-deb >/dev/null 2>&1 \
  && dpkg-deb --info "$DEB_PATH" >/dev/null 2>&1 \
  && dpkg-deb -e "$DEB_PATH" "$CONTROL_DIR" >/dev/null 2>&1 \
  && dpkg-deb -x "$DEB_PATH" "$DATA_DIR" >/dev/null 2>&1; then
  echo 'OK: dpkg-deb info/control/data extraction passed'
  record_check e1 'deb archive readable and extractable' passed
else
  echo 'FAIL: missing/invalid DEB or dpkg-deb extraction failed'
  record_check e1 'deb archive readable and extractable' failed
fi

# e2: control profile and app identity
printf '%s\n' '== e2. control fields match RootHide package profile =='
if [[ -f "$CONTROL_FILE" && -f "$APP_DIR/Info.plist" ]]; then
  pkg="$(awk -F': *' '$1 == "Package" {print $2; exit}' "$CONTROL_FILE" | tr -d '\r')"
  ver="$(awk -F': *' '$1 == "Version" {print $2; exit}' "$CONTROL_FILE" | tr -d '\r')"
  arch="$(awk -F': *' '$1 == "Architecture" {print $2; exit}' "$CONTROL_FILE" | tr -d '\r')"
  depends="$(awk -F': *' '$1 == "Depends" {print $2; exit}' "$CONTROL_FILE" | tr -d '\r')"
  bundle="$(python3 - "$APP_DIR/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    print(plistlib.load(f).get('CFBundleIdentifier', ''))
PY
)"
  e2_fail=0
  app_version="$(python3 - "$APP_DIR/Info.plist" <<'PYVERSION'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    print(plistlib.load(f).get('CFBundleShortVersionString', ''))
PYVERSION
)"
  deb_version_base="$(printf '%s' "$ver" | sed -E 's/-[0-9]+$//')"
  [[ -n "$pkg" && -n "$ver" && -n "$arch" && "$pkg" == "$bundle" ]] || e2_fail=1
  [[ -n "$app_version" && "$deb_version_base" == "$app_version" ]] || e2_fail=1
  [[ "$arch" == "$DEB_PACKAGE_ARCH" ]] || e2_fail=1
  [[ "$depends" == *"$DEB_REQUIRED_DEPENDS_PATTERN"* ]] || e2_fail=1
  if [[ "$e2_fail" -eq 0 ]]; then
    echo "OK: Package=$pkg BundleID=$bundle AppVersion=$app_version ControlVersion=$ver PackageArchitecture=$arch Depends=$depends"
    record_check e2 'control fields and RootHide profile' passed
  else
    echo "FAIL: Package=$pkg BundleID=$bundle AppVersion=${app_version:-<empty>} ControlVersion=$ver Architecture=$arch Depends=$depends (version base must match AppVersion)"
    record_check e2 'control fields and RootHide profile' failed
  fi
else
  echo 'FAIL: control or extracted App Info.plist missing'
  record_check e2 'control fields and RootHide profile' failed
fi

# e3: exact approved postinst plus shell syntax; do not broaden its capabilities.
printf '%s\n' '== e3. postinst is the approved registration-only script =='
if [[ -f "$POSTINST_FILE" ]] && sh -n "$POSTINST_FILE" \
  && cmp -s "$POSTINST_FILE" Config/DEB/postinst; then
  echo 'OK: postinst syntax valid and byte-identical to reviewed source'
  record_check e3 'postinst registration-only policy' passed
else
  echo 'FAIL: postinst missing, syntax-invalid, or differs from reviewed source'
  record_check e3 'postinst registration-only policy' failed
fi

# e4: RootHide rootfs-relative layout; reject ordinary Rootless prefix.
printf '%s\n' '== e4. RootHide payload path and no var/jb prefix =='
if [[ -d "$APP_DIR" ]] && ! find "$DATA_DIR" -path '*/var/jb/*' -print -quit | grep -q .; then
  echo "OK: $DEB_PAYLOAD_RELATIVE_PATH present; no var/jb prefix"
  record_check e4 'RootHide rootfs-relative payload path' passed
else
  echo 'FAIL: App payload missing or Rootless var/jb prefix detected'
  record_check e4 'RootHide rootfs-relative payload path' failed
fi

# e5: every payload archive entry must be root:root (GNU tar and bsdtar formats).
printf '%s\n' '== e5. payload ownership root:root =='
if [[ -n "$DEB_PATH" && -f "$DEB_PATH" ]] && command -v tar >/dev/null 2>&1; then
  ownership_bad="$(dpkg-deb --fsys-tarfile "$DEB_PATH" 2>/dev/null | tar -tvf - 2>/dev/null | awk '
    function norm(v) { if (v == "0" || v == "root") return "root"; return v }
    {
      if ($2 ~ /\//) { split($2, pair, "/"); owner=pair[1]; group=pair[2] }
      else { owner=$3; group=$4 }
      if (norm(owner) != "root" || norm(group) != "root") { print; bad=1 }
    }
    END { exit bad }
  ' 2>&1)" || true
  if [[ -z "$ownership_bad" ]]; then
    echo 'OK: archive entries are root:root'
    record_check e5 'payload ownership root:root' passed
  else
    echo "FAIL: non-root ownership detected: ${ownership_bad:0:500}"
    record_check e5 'payload ownership root:root' failed
  fi
else
  echo 'unavailable: dpkg-deb/tar unavailable'
  record_check e5 'payload ownership root:root' unavailable
fi

# e6: Info.plist executable exists and is executable in the extracted bundle.
printf '%s\n' '== e6. CFBundleExecutable exists and is executable =='
if [[ -f "$APP_DIR/Info.plist" ]]; then
  exec_name="$(python3 - "$APP_DIR/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    value = plistlib.load(f).get('CFBundleExecutable', '')
print(value if isinstance(value, str) else '')
PY
)"
  if [[ -n "$exec_name" && -f "$APP_DIR/$exec_name" && -x "$APP_DIR/$exec_name" ]]; then
    echo "OK: CFBundleExecutable=$exec_name"
    record_check e6 'bundle executable present and executable' passed
  else
    echo "FAIL: CFBundleExecutable invalid/missing: ${exec_name:-<empty>}"
    record_check e6 'bundle executable present and executable' failed
  fi
else
  echo 'FAIL: Info.plist missing'
  record_check e6 'bundle executable present and executable' failed
fi

# e7: compare complete source and packaged bundle, including bytes, symlinks and exec bits.
printf '%s\n' '== e7. source App and DEB payload parity =='
if [[ -n "$SOURCE_APP_PATH" && -d "$SOURCE_APP_PATH" && -d "$APP_DIR" ]]; then
  compare_json="$(python3 scripts/compare-app-bundles.py --source "$SOURCE_APP_PATH" --packaged "$APP_DIR" 2>&1)"
  compare_rc=$?
  echo "$compare_json"
  if [[ "$compare_rc" -eq 0 ]]; then
    record_check e7 'source and packaged App bundle parity' passed
  else
    record_check e7 'source and packaged App bundle parity' failed
  fi
else
  echo 'unavailable: SOURCE_APP_PATH not supplied; full tree parity not established'
  record_check e7 'source and packaged App bundle parity' unavailable
fi

# e8: inspect Mach-O architecture separately from dpkg control Architecture.
printf '%s\n' '== e8. Mach-O device architecture includes arm64 =='
APP_EXECUTABLE_PATH=""
if [[ -n "${exec_name:-}" ]]; then APP_EXECUTABLE_PATH="$APP_DIR/$exec_name"; fi
if [[ -n "$APP_EXECUTABLE_PATH" && -f "$APP_EXECUTABLE_PATH" ]] && command -v lipo >/dev/null 2>&1; then
  archs="$(lipo -archs "$APP_EXECUTABLE_PATH" 2>/dev/null || true)"
  case " $archs " in
    *" $DEB_MINIMUM_BINARY_ARCH "*)
      echo "OK: Mach-O slices=$archs (package Architecture=$DEB_PACKAGE_ARCH is a separate field)"
      record_check e8 'Mach-O includes minimum device architecture' passed ;;
    *)
      echo "FAIL: Mach-O slices=${archs:-<unreadable>}; expected $DEB_MINIMUM_BINARY_ARCH"
      record_check e8 'Mach-O includes minimum device architecture' failed ;;
  esac
else
  echo 'unavailable: lipo or executable unavailable; architecture not inferred from DEB control'
  record_check e8 'Mach-O includes minimum device architecture' unavailable
fi

# e9: validate ldid signature, LC_CODE_SIGNATURE and the exact embedded entitlements.
printf '%s\n' '== e9. ldid signature + LC_CODE_SIGNATURE + embedded entitlements =='
SIGNATURE_STATE='unavailable'
LDID_SUMMARY_PATH="$WORKDIR/ldid-signature-summary.json"
if [[ -d "$APP_DIR" ]] && command -v ldid >/dev/null 2>&1 \
  && command -v otool >/dev/null 2>&1 && command -v file >/dev/null 2>&1; then
  if LDID_SIGNATURE_SUMMARY_PATH="$LDID_SUMMARY_PATH" \
       bash scripts/validate-ldid-signature.sh "$APP_DIR"; then
    SIGNATURE_STATE='ldid_signed_static_valid'
    record_check e9 'ldid signature and embedded entitlements' passed
  else
    SIGNATURE_STATE='ldid_signature_invalid'
    record_check e9 'ldid signature and embedded entitlements' failed
  fi
else
  echo 'unavailable: ldid/otool/file unavailable; signed state cannot be established'
  record_check e9 'ldid signature and embedded entitlements' unavailable
fi

# Candidate classification is deliberately separate from device installability.
ARTIFACT_CLASS='ldid-signed-candidate'
DEVICE_INSTALL_STATUS='not-tested'
DEVICE_INSTALLABLE='false'
if [[ "$DEB_PATH" != *.ldid-signed-candidate.deb ]]; then
  echo "FAIL: DEB filename must end in .ldid-signed-candidate.deb: $DEB_PATH"
  record_check e10 'signed candidate artifact classification' failed
else
  echo 'OK: artifact is explicitly classified as ldid-signed-candidate; device installability remains unproven'
  record_check e10 'signed candidate artifact classification' passed
fi

# JSON summary (simple fixed labels; no user-controlled strings are interpolated).
json_checks='['
for i in "${!check_ids[@]}"; do
  [[ "$i" -gt 0 ]] && json_checks+=','
  json_checks+="{\"id\":\"${check_ids[$i]}\",\"name\":\"${check_names[$i]}\",\"status\":\"${check_status[$i]}\"}"
done
json_checks+=']'
DEB_SHA256='unavailable'
if [[ -n "$DEB_PATH" && -f "$DEB_PATH" ]]; then
  if command -v shasum >/dev/null 2>&1; then DEB_SHA256="$(shasum -a 256 "$DEB_PATH" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then DEB_SHA256="$(sha256sum "$DEB_PATH" | awk '{print $1}')"; fi
fi
summary="{\"profile\":\"$DEB_PROFILE_ID\",\"packageArchitecture\":\"$DEB_PACKAGE_ARCH\",\"minimumMachOArchitecture\":\"$DEB_MINIMUM_BINARY_ARCH\",\"artifactClass\":\"$ARTIFACT_CLASS\",\"signatureState\":\"$SIGNATURE_STATE\",\"deviceInstallStatus\":\"$DEVICE_INSTALL_STATUS\",\"deviceInstallable\":$DEVICE_INSTALLABLE,\"sha256\":\"$DEB_SHA256\",\"checks\":$json_checks,\"failed\":$fail,\"validator\":\"validate-deb\"}"
echo '--- summary ---'
echo "$summary"
if [[ -n "$SUMMARY_PATH" ]]; then
  mkdir -p "$(dirname "$SUMMARY_PATH")"
  printf '%s\n' "$summary" > "$SUMMARY_PATH"
fi
exit "$fail"
