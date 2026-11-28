#!/usr/bin/env bash
# P2-45-R1: read-only Darwin/Xcode build and signing qualification.
# This script never changes signing settings, installs artifacts, or opens write gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: P2-45-R1 requires macOS; current host is $(uname -s)."
  echo "No Apple SDK build, codesign verification, or signing identity inspection was performed."
  exit 3
fi

for tool in xcodebuild xcodegen codesign security; do
  command -v "$tool" >/dev/null 2>&1 || { echo "BLOCKED: required tool missing: $tool" >&2; exit 4; }
done

OUT="${P245_R1_OUT:-$ROOT/Build/DeviceAcceptance/P2-45-R1}"
mkdir -p "$OUT"

xcodegen generate --spec "$ROOT/Project.yml" --project "$ROOT/FilterKit.xcodeproj"
xcodebuild -version | tee "$OUT/xcode-version.txt"
xcodebuild -showsdks | tee "$OUT/apple-sdks.txt"
xcodebuild -list -project "$ROOT/FilterKit.xcodeproj" | tee "$OUT/xcode-targets.txt"

# Compile-only build: deliberately unsigned. Release signing is a separate gate.
xcodebuild -project "$ROOT/FilterKit.xcodeproj" -scheme FilterKit \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO build \
  | tee "$OUT/unsigned-ios-build.log"

APP="$OUT/DerivedData/Build/Products/Release-iphoneos/FilterKit.app"
[[ -d "$APP" ]] || { echo "BLOCKED: expected app product missing: $APP" >&2; exit 5; }

# Do not treat an unsigned compile product as a release artifact.
echo "BLOCKED: compile-only build completed; signed App/Helper artifacts and release identity are still required."
echo "Next: produce the exact jailbreak-signed Helper and App artifacts, then run the signed-artifact preflight."
exit 6
