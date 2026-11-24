#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/FilterKit.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-FilterKit}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: XcodeGen is required. Install with: brew install xcodegen" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 1
fi

cd "$ROOT"
xcodegen generate --spec Project.yml
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -destination "$DESTINATION" -derivedDataPath "$ROOT/.build/DerivedData" CODE_SIGNING_ALLOWED=NO build
