#!/bin/bash
# Inspect already-signed artifacts; does not sign, install, or modify them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: codesign inspection requires macOS." >&2; exit 2
fi
for tool in codesign shasum plutil; do command -v "$tool" >/dev/null 2>&1 || { echo "BLOCKED: missing $tool" >&2; exit 2; }; done
: "${FILTERKIT_SIGNED_APP:?Set FILTERKIT_SIGNED_APP to the signed .app path}"
: "${FILTERKIT_SIGNED_HELPER:?Set FILTERKIT_SIGNED_HELPER to the signed Helper executable path}"
: "${FILTERKIT_EXPECTED_TEAM_ID:?Set FILTERKIT_EXPECTED_TEAM_ID to the expected TeamIdentifier}"
ART="$ROOT/Build/Artifacts/P2-37-R8-Signed-Artifact-Inspection"
mkdir -p "$ART"
inspect() {
  local label="$1" path="$2"
  [[ -e "$path" ]] || { echo "FAIL: $label not found: $path" >&2; exit 1; }
  codesign --verify --strict --verbose=2 "$path" 2>&1 | tee "$ART/$label-Verify.log"
  codesign -dv --verbose=4 "$path" 2> "$ART/$label-CodeSignature.txt"
  grep -F "TeamIdentifier=$FILTERKIT_EXPECTED_TEAM_ID" "$ART/$label-CodeSignature.txt" >/dev/null || {
    echo "FAIL: $label TeamIdentifier mismatch" >&2; exit 1;
  }
  grep -E '^CDHash=' "$ART/$label-CodeSignature.txt" >/dev/null || {
    echo "FAIL: $label CDHash missing" >&2; exit 1;
  }
  codesign -d --entitlements :- "$path" > "$ART/$label-Entitlements.plist" 2> "$ART/$label-Entitlements.log"
  plutil -lint "$ART/$label-Entitlements.plist"
}
inspect FilterKit-App "$FILTERKIT_SIGNED_APP"
inspect FilterKit-Helper "$FILTERKIT_SIGNED_HELPER"
cat <<MSG
PASS: both signatures verify and TeamIdentifier matches $FILTERKIT_EXPECTED_TEAM_ID.
Review the captured entitlements and CDHash values against the release trust manifest.
This inspection alone does not establish runtime entitlements or peer-authentication success.
MSG
