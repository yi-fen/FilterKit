#!/bin/sh
# Run on macOS with Xcode and XcodeGen installed. Does not enable runtime write gates.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null 2>&1 || { echo 'ERROR: xcodegen is required' >&2; exit 2; }
command -v xcodebuild >/dev/null 2>&1 || { echo 'ERROR: xcodebuild is required (run on macOS)' >&2; exit 2; }

xcodegen generate --spec Project.yml
PROJECT="$ROOT/FilterKit.xcodeproj"
DESTINATION='generic/platform=iOS Simulator'

xcodebuild -project "$PROJECT" -target FilterKitHelper -sdk iphonesimulator \
  -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "$PROJECT" -scheme FilterKit -sdk iphonesimulator \
  -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO test
