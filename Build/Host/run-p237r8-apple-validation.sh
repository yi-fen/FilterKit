#!/bin/bash
# P2-37-R8 Apple SDK validation. Build/test only; never installs or opens production write gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: P2-37-R8 requires macOS; current host is $(uname -s)." >&2
  exit 2
fi
for tool in xcodebuild xcrun xcodegen python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "BLOCKED: missing required tool: $tool" >&2; exit 2; }
done
: "${FILTERKIT_SIMULATOR_UDID:?Set FILTERKIT_SIMULATOR_UDID to an available iOS Simulator UDID}"

ART="$ROOT/Build/Artifacts/P2-37-R8"
mkdir -p "$ART"
python3 "$ROOT/Build/scripts/p237r8_apple_readiness_audit.py" | tee "$ART/Readiness-Audit.log"
xcodebuild -version | tee "$ART/Xcode-Version.txt"
xcrun --sdk iphoneos --show-sdk-version | tee "$ART/iPhoneOS-SDK-Version.txt"
xcrun --sdk iphonesimulator --show-sdk-version | tee "$ART/Simulator-SDK-Version.txt"
xcrun simctl list devices available > "$ART/Available-Simulators.txt"

# SDK importer probe: compile-time only, no syscall execution.
xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -typecheck \
  "$ROOT/Build/DarwinSDK/FilterKitDarwinSDKProbe.swift" \
  2>&1 | tee "$ART/Darwin-iPhoneOS-Probe.log"
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -typecheck \
  "$ROOT/Build/DarwinSDK/FilterKitDarwinSDKProbe.swift" \
  2>&1 | tee "$ART/Darwin-Simulator-Probe.log"

xcodegen generate --spec "$ROOT/Project.yml" --project "$ART/FilterKit.xcodeproj"
PROJECT="$ART/FilterKit.xcodeproj"
DEST="platform=iOS Simulator,id=$FILTERKIT_SIMULATOR_UDID"

xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphonesimulator \
  -configuration Debug -destination "$DEST" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/Helper-Simulator-Build.log"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -configuration Debug -destination "$DEST" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/App-Simulator-Build.log"
RESULT="$ART/FilterKit-XCTest.xcresult"
rm -rf "$RESULT"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -configuration Debug -destination "$DEST" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$RESULT" test \
  2>&1 | tee "$ART/XCTest.log"

xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/Helper-iPhoneOS-Build.log"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphoneos \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$ART/App-iPhoneOS-Build.log"

cat <<'MSG'
PASS: Darwin SDK probes, simulator Helper/App builds, XCTest, and generic iPhoneOS builds.
NOT DONE: signed artifact trust acceptance, on-device peer identity, RootHide/ElleKit runtime, transaction-on-device.
Production activation commit gates must remain closed.
MSG
