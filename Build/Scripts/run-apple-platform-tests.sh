#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${FILTERKIT_TEST_DESTINATION:?Set FILTERKIT_TEST_DESTINATION, e.g. 'platform=iOS Simulator,id=<simulator-udid>'}"
command -v xcodegen >/dev/null 2>&1 || { echo "FAIL: xcodegen is required" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "FAIL: xcodebuild is required" >&2; exit 1; }
case "$(uname -s)" in Darwin) ;; *) echo "FAIL: Apple platform tests must run on macOS" >&2; exit 1 ;; esac
PROJECT_DIR="$ROOT/Build/Generated"
mkdir -p "$PROJECT_DIR"
xcodegen generate --spec "$ROOT/Project.yml" --project "$PROJECT_DIR/FilterKit.xcodeproj"
xcodebuild test \
  -project "$PROJECT_DIR/FilterKit.xcodeproj" \
  -scheme FilterKit \
  -destination "$FILTERKIT_TEST_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO
