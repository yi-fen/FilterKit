#!/bin/sh
# Full Apple SDK/XCTest run. Requires macOS, Xcode, and XcodeGen.
# The tests use only temporary fixture directories; production Release Gates remain false.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null 2>&1 || { echo 'ERROR: xcodegen is required' >&2; exit 2; }
command -v xcodebuild >/dev/null 2>&1 || { echo 'ERROR: xcodebuild is required (run on macOS)' >&2; exit 2; }
python3 "$ROOT/Build/scripts/p236r2_phase2_transaction_audit.py"
xcodegen generate --spec Project.yml
mkdir -p "$ROOT/Build/Artifacts"
RESULT="$ROOT/Build/Artifacts/P2-36-R2-Phase2.xcresult"
rm -rf "$RESULT"
xcodebuild -project "$ROOT/FilterKit.xcodeproj" -scheme FilterKit \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO -resultBundlePath "$RESULT" test
