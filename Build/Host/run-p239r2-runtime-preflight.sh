#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

printf '%s\n' '== P2-39-R2 Runtime Acceptance Preflight =='

bash Build/Host/run-p239r1-scan-reduction-acceptance.sh
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
printf '%s\n' 'PASS | Swift source parse (Sources, App, HelperRuntime, UnitTests)'

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'BLOCKED | Apple build and device XCTest require macOS/Xcode.'
  printf '%s\n' 'BLOCKED | RootHide/ElleKit runtime acceptance requires a connected test device.'
  exit 0
fi

for tool in xcodebuild xcodegen xcrun; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'BLOCKED | Required tool not found: %s\n' "$tool"
    exit 2
  fi
done

if [[ ! -d FilterKit.xcodeproj ]]; then
  xcodegen generate --spec Project.yml
fi

mkdir -p Build/DeviceAcceptance/Results
BUILD_LOG="Build/DeviceAcceptance/Results/p239r2-build-$(date +%Y%m%d-%H%M%S).log"
xcodebuild build -project FilterKit.xcodeproj -scheme FilterKit \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO | tee "$BUILD_LOG"
printf 'PASS | Generic iOS SDK build; log: %s\n' "$BUILD_LOG"

UDID="${FILTERKIT_DEVICE_UDID:-}"
if [[ -z "$UDID" ]]; then
  printf '%s\n' 'BLOCKED | Set FILTERKIT_DEVICE_UDID to run XCTest on the connected device.'
  exit 0
fi

RESULT="Build/DeviceAcceptance/Results/P2-39-R2-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild test -project FilterKit.xcodeproj -scheme FilterKit \
  -destination "platform=iOS,id=${UDID}" \
  -resultBundlePath "$RESULT" | tee "${RESULT%.xcresult}.log"
printf 'PASS | Device XCTest completed; result: %s\n' "$RESULT"
printf '%s\n' 'MANUAL | Complete the RootHide/ElleKit navigation and attestation scenarios in Build/DeviceAcceptance/P2-39-R2-RUNTIME-ACCEPTANCE.md.'
