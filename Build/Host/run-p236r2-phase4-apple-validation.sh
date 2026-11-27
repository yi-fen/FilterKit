#!/bin/bash
# Phase 4 Apple SDK build gate. Does not install to a device or open production write gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: Phase 4 Apple validation requires macOS; current host is $(uname -s)." >&2
  exit 2
fi
for tool in xcodebuild xcrun xcodegen; do
  command -v "$tool" >/dev/null 2>&1 || { echo "BLOCKED: $tool is required." >&2; exit 2; }
done
: "${FILTERKIT_SIMULATOR_UDID:?Set FILTERKIT_SIMULATOR_UDID to an available iOS Simulator UDID}"

mkdir -p "$ROOT/Build/Artifacts"
ART="$ROOT/Build/Artifacts"
python3 "$ROOT/Build/scripts/p236r2_phase4_apple_gate_audit.py"

xcodebuild -version | tee "$ART/P2-36-R2-Phase4-Xcode-Version.txt"
xcrun --sdk iphoneos --show-sdk-version | tee "$ART/P2-36-R2-Phase4-iPhoneOS-SDK-Version.txt"
xcrun --sdk iphonesimulator --show-sdk-version | tee "$ART/P2-36-R2-Phase4-Simulator-SDK-Version.txt"

# Validate Darwin SDK declarations/imports for both device and simulator SDKs.
xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -typecheck \
  "$ROOT/Build/DarwinSDK/FilterKitDarwinSDKProbe.swift" \
  2>&1 | tee "$ART/P2-36-R2-Phase4-Darwin-iPhoneOS-Probe.log"
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -typecheck \
  "$ROOT/Build/DarwinSDK/FilterKitDarwinSDKProbe.swift" \
  2>&1 | tee "$ART/P2-36-R2-Phase4-Darwin-Simulator-Probe.log"

xcodegen generate --spec Project.yml
PROJECT="$ROOT/FilterKit.xcodeproj"
SIM_DEST="platform=iOS Simulator,id=$FILTERKIT_SIMULATOR_UDID"

# Simulator builds catch SDK importer, Swift type-checker and linker errors.
xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphonesimulator \
  -configuration Debug -destination "$SIM_DEST" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/P2-36-R2-Phase4-Helper-Simulator-Build.log"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -configuration Debug -destination "$SIM_DEST" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/P2-36-R2-Phase4-App-Simulator-Build.log"

RESULT="$ART/P2-36-R2-Phase4-XCTest.xcresult"
rm -rf "$RESULT"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -configuration Debug -destination "$SIM_DEST" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$RESULT" test \
  2>&1 | tee "$ART/P2-36-R2-Phase4-XCTest.log"

# Generic device SDK builds validate the iPhoneOS compilation/linking path without signing.
xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/P2-36-R2-Phase4-Helper-iPhoneOS-Build.log"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/P2-36-R2-Phase4-App-iPhoneOS-Build.log"

cat <<'MSG'
PASS: Darwin SDK importer probes, simulator builds, XCTest, and generic iPhoneOS builds completed.
NOT DONE: signed deployment, on-device LOCAL_PEERTOKEN/csops verification, RootHide runtime test.
Production plugin-association Release Gates must remain closed pending device evidence review.
MSG
