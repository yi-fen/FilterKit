#!/bin/sh
# Apple-platform validation. Must run on macOS with Xcode, XcodeGen and an available iOS Simulator.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null 2>&1 || { echo 'ERROR: xcodegen is required' >&2; exit 2; }
command -v xcodebuild >/dev/null 2>&1 || { echo 'ERROR: xcodebuild is required (run on macOS)' >&2; exit 2; }
command -v xcrun >/dev/null 2>&1 || { echo 'ERROR: xcrun is required' >&2; exit 2; }
: "${FILTERKIT_SIMULATOR_UDID:?Set FILTERKIT_SIMULATOR_UDID to an available iOS Simulator UDID}"
python3 "$ROOT/Build/scripts/p236r2_phase3_integration_audit.py"
xcodegen generate --spec Project.yml
mkdir -p "$ROOT/Build/Artifacts"
PROJECT="$ROOT/FilterKit.xcodeproj"
DESTINATION="platform=iOS Simulator,id=$FILTERKIT_SIMULATOR_UDID"

xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphonesimulator \
  -configuration Debug -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO build \
  | tee "$ROOT/Build/Artifacts/P2-36-R2-Phase3-Helper-Build.log"

xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -configuration Debug -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO build \
  | tee "$ROOT/Build/Artifacts/P2-36-R2-Phase3-App-Build.log"

RESULT="$ROOT/Build/Artifacts/P2-36-R2-Phase3-Tests.xcresult"
rm -rf "$RESULT"
xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -configuration Debug -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$RESULT" test \
  | tee "$ROOT/Build/Artifacts/P2-36-R2-Phase3-XCTest.log"

printf '%s\n' 'PASS FilterKitHelper iOS Simulator build' \
              'PASS FilterKit iOS Simulator build' \
              'PASS FilterKit XCTest suite'
