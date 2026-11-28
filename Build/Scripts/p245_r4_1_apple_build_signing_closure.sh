#!/usr/bin/env bash
# P2-45-R4.1: build and sign App + standalone Helper with one explicit Apple identity.
# This script creates artifacts only. It never installs, bootstraps launchd, or opens write gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: P2-45-R4.1 requires macOS; current host is $(uname -s)." >&2
  exit 2
fi
for tool in xcodebuild xcodegen codesign security xcrun python3 rsync shasum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "BLOCKED: missing required tool: $tool" >&2; exit 2; }
done
: "${FILTERKIT_CODESIGN_IDENTITY:?Set to the SHA-1 fingerprint of the Apple Development/Distribution identity}"
: "${FILTERKIT_EXPECTED_TEAM_ID:?Set the expected 10-character Apple Team ID}"
: "${FILTERKIT_PROVISIONING_PROFILE_SPECIFIER:?Set the device-installable provisioning profile name}"
: "${FILTERKIT_TRUST_GENERATION:?Set a positive monotonically increasing trust generation}"
[[ "$FILTERKIT_EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "BLOCKED: invalid Team ID" >&2; exit 2; }
[[ "$FILTERKIT_TRUST_GENERATION" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCKED: invalid trust generation" >&2; exit 2; }

ART="${FILTERKIT_R4_1_OUT:-$ROOT/Build/Artifacts/P2-45-R4.1}"
mkdir -p "$ART"
ART="$(cd "$ART" && pwd)"
[[ "$ART" != "/" && "$ART" != "$ROOT" ]] || { echo "BLOCKED: unsafe artifact output directory" >&2; exit 2; }
SRC="$ART/Source"
PROJECT="$ART/FilterKit.xcodeproj"
rm -rf "$SRC" "$PROJECT" "$ART/DerivedData" "$ART/Helper" "$ART/Release"
mkdir -p "$SRC"
rsync -a --delete --exclude '.git' --exclude 'Build/Artifacts' "$ROOT/" "$SRC/"

IDENTITIES="$(security find-identity -v -p codesigning 2>&1)"
printf '%s\n' "$IDENTITIES" | grep -F "$FILTERKIT_CODESIGN_IDENTITY" >/dev/null || {
  echo "BLOCKED: requested signing identity is not present in the keychain" >&2; exit 3;
}
xcodebuild -version | tee "$ART/Xcode-Version.txt"
xcrun --sdk iphoneos --show-sdk-version | tee "$ART/iPhoneOS-SDK-Version.txt"

# Generate a clean XcodeGen project from the isolated source copy.
xcodegen generate --spec "$SRC/Project.yml" --project "$PROJECT"

# Build Helper as a standalone iOS arm64 tool without Xcode's App-bundle signing assumptions.
xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$ART/DerivedData" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/Helper-Unsigned-Build.log"
HELPER_UNSIGNED="$ART/DerivedData/Build/Products/Release-iphoneos/FilterKitHelper"
[[ -f "$HELPER_UNSIGNED" ]] || { echo "BLOCKED: Helper executable product missing" >&2; exit 4; }
mkdir -p "$ART/Helper"
cp "$HELPER_UNSIGNED" "$ART/Helper/filterkit-helper"

# Sign the standalone Helper with the same Apple identity used for the App.
codesign --force --sign "$FILTERKIT_CODESIGN_IDENTITY" \
  --identifier cn.yfen.filterkit.helper --timestamp=none "$ART/Helper/filterkit-helper"
codesign --verify --strict --verbose=2 "$ART/Helper/filterkit-helper" 2>&1 | tee "$ART/Helper-Signature-Verify.log"
codesign -dv --verbose=4 "$ART/Helper/filterkit-helper" 2> "$ART/Helper-CodeSignature.txt"
grep -F "Identifier=cn.yfen.filterkit.helper" "$ART/Helper-CodeSignature.txt" >/dev/null
grep -F "TeamIdentifier=$FILTERKIT_EXPECTED_TEAM_ID" "$ART/Helper-CodeSignature.txt" >/dev/null || {
  echo "BLOCKED: signed Helper does not expose the expected TeamIdentifier" >&2; exit 5;
}
HELPER_CDHASH="$(sed -n 's/^CDHash=//p' "$ART/Helper-CodeSignature.txt" | head -1)"
[[ "$HELPER_CDHASH" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "BLOCKED: Helper CDHash unavailable" >&2; exit 5; }

# Embed the final Helper CDHash before the App is signed; this avoids self-referential App pinning.
python3 - "$SRC/Resources/FilterKit-Helper-AppTrust.json" "$FILTERKIT_TRUST_GENERATION" "$HELPER_CDHASH" <<'PY'
import json, pathlib, sys
out, generation, cdhash = sys.argv[1], int(sys.argv[2]), sys.argv[3].lower()
payload = {
    "schemaVersion": 1,
    "bundleIdentifier": "cn.yfen.filterkit",
    "allowedHelperCDHashes": [cdhash],
    "generation": generation,
    "allowedHelperUIDs": [0],
    "allowedHelperGIDs": [0]
}
pathlib.Path(out).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

# Regenerate so the trust resource is included in the App target, then sign the App via Xcode.
xcodegen generate --spec "$SRC/Project.yml" --project "$PROJECT"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$ART/DerivedData" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$FILTERKIT_CODESIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$FILTERKIT_EXPECTED_TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$FILTERKIT_PROVISIONING_PROFILE_SPECIFIER" build \
  2>&1 | tee "$ART/App-Signed-Build.log"
APP="$ART/DerivedData/Build/Products/Release-iphoneos/FilterKit.app"
[[ -d "$APP" ]] || { echo "BLOCKED: signed App product missing" >&2; exit 6; }
[[ -f "$APP/embedded.mobileprovision" ]] || { echo "BLOCKED: App provisioning profile missing" >&2; exit 6; }
[[ -f "$APP/FilterKit-Helper-AppTrust.json" ]] || { echo "BLOCKED: Helper trust resource missing from App" >&2; exit 6; }

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee "$ART/App-Signature-Verify.log"
codesign -dv --verbose=4 "$APP" 2> "$ART/App-CodeSignature.txt"
grep -F "Identifier=cn.yfen.filterkit" "$ART/App-CodeSignature.txt" >/dev/null
grep -F "TeamIdentifier=$FILTERKIT_EXPECTED_TEAM_ID" "$ART/App-CodeSignature.txt" >/dev/null || {
  echo "BLOCKED: signed App TeamIdentifier mismatch" >&2; exit 7;
}
APP_CDHASH="$(sed -n 's/^CDHash=//p' "$ART/App-CodeSignature.txt" | head -1)"
[[ "$APP_CDHASH" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "BLOCKED: App CDHash unavailable" >&2; exit 7; }

# Verify provisioning profile's Team and application identifier match the signed App.
security cms -D -i "$APP/embedded.mobileprovision" > "$ART/App-Provisioning-Profile.plist"
python3 - "$ART/App-Provisioning-Profile.plist" "$FILTERKIT_EXPECTED_TEAM_ID" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], 'rb'))
team = sys.argv[2]
assert team in p.get('TeamIdentifier', []), 'profile TeamIdentifier mismatch'
e = p.get('Entitlements', {})
assert e.get('application-identifier', '').endswith('.cn.yfen.filterkit'), 'profile application-identifier mismatch'
assert p.get('ExpirationDate') is not None, 'profile expiration missing'
PY

mkdir -p "$ART/Release"
cp -R "$APP" "$ART/Release/FilterKit.app"
cp "$ART/Helper/filterkit-helper" "$ART/Release/filterkit-helper"
shasum -a 256 "$ART/Release/filterkit-helper" > "$ART/Release-SHA256.txt"
shasum -a 256 "$ART/Release/FilterKit.app/FilterKit-Helper-AppTrust.json" >> "$ART/Release-SHA256.txt"
cat > "$ART/Release/Identity-Summary.txt" <<SUMMARY
App Bundle ID: cn.yfen.filterkit
Helper Signing Identifier: cn.yfen.filterkit.helper
Team ID: $FILTERKIT_EXPECTED_TEAM_ID
App CDHash: $APP_CDHASH
Helper CDHash: $HELPER_CDHASH
Trust Generation: $FILTERKIT_TRUST_GENERATION
Provisioning Profile: $FILTERKIT_PROVISIONING_PROFILE_SPECIFIER
SUMMARY

cat <<MSG
PASS: signed App and standalone Helper artifacts were built and signature/profile metadata matched.
Artifacts: $ART/Release
NOT DONE: device installation, launchd bootstrap, RootHide IPC, APFS transaction acceptance.
Production write gates remain closed.
MSG
