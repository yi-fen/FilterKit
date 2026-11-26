#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${1:-iphoneos}"
TARGET="${2:-arm64-apple-ios15.0}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "BLOCKED: xcrun is unavailable; run this gate on macOS with Xcode installed." >&2
  exit 2
fi
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
[[ -d "$SDK_PATH" ]] || { echo "BLOCKED: SDK path does not exist: $SDK_PATH" >&2; exit 2; }

echo "SDK: $SDK_PATH"
echo "Target: $TARGET"
xcrun --sdk "$SDK" swiftc -target "$TARGET" -typecheck \
  "$ROOT/Build/DarwinSDK/FilterKitDarwinSDKProbe.swift"

if command -v xcodegen >/dev/null 2>&1; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  xcodegen generate --spec "$ROOT/Project.yml" --project "$TMP/FilterKit.xcodeproj"
  xcodebuild -project "$TMP/FilterKit.xcodeproj" -scheme FilterKitHelper \
    -sdk "$SDK" -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "NOTE: xcodegen unavailable; project generation/build skipped."
fi
