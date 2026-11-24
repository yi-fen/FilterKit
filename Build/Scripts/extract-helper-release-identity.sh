#!/bin/bash
# macOS release helper: extracts identity from the FINAL signed Helper binary.
# Usage: extract-helper-release-identity.sh <helper-binary> <release-id> <generation> <bundle-id> <version> <output.json> [--pin-publisher]
set -euo pipefail
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 6 || $# -gt 7 ]]; then
  echo "Usage: $0 <helper-binary> <release-id> <generation> <bundle-id> <version> <output.json> [--pin-publisher]" >&2
  exit 2
fi
HELPER=$1 RELEASE=$2 GENERATION=$3 BUNDLE=$4 VERSION=$5 OUTPUT=$6 POLICY=${7:-}
HELPER="$(cd "$(dirname "$HELPER")" && pwd)/$(basename "$HELPER")"
[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: codesign identity extraction requires macOS" >&2; exit 3; }
[[ -f "$HELPER" && ! -L "$HELPER" ]] || { echo "ERROR: Helper must be a regular non-symlink file" >&2; exit 4; }
[[ "$GENERATION" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: generation must be a positive integer" >&2; exit 4; }
INFO=$(codesign -dvvv --verbose=4 "$HELPER" 2>&1) || { echo "ERROR: codesign inspection failed" >&2; exit 5; }
CDHASH=$(printf '%s\n' "$INFO" | sed -n 's/^CDHash=//p' | head -n 1 | tr '[:upper:]' '[:lower:]' )
IDENTIFIER=$(printf '%s\n' "$INFO" | sed -n 's/^Identifier=//p' | head -n 1)
TEAM=$(printf '%s\n' "$INFO" | sed -n 's/^TeamIdentifier=//p' | head -n 1)
[[ "$CDHASH" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: unable to extract a valid CDHash" >&2; exit 6; }
[[ "$IDENTIFIER" == "$BUNDLE" ]] || { echo "ERROR: signed Identifier does not match requested bundle identifier" >&2; exit 6; }
SHA=$(shasum -a 256 "$HELPER" | awk '{print tolower($1)}')
CERT_SHA=""
if [[ "$POLICY" == "--pin-publisher" ]]; then
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "ERROR: signed TeamIdentifier missing or invalid" >&2; exit 7; }
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  (cd "$TMP" && codesign -d --extract-certificates "$HELPER" >/dev/null 2>&1) || { echo "ERROR: cannot extract signing certificate" >&2; exit 7; }
  [[ -f "$TMP/codesign0" ]] || { echo "ERROR: leaf signing certificate missing" >&2; exit 7; }
  CERT_SHA=$(shasum -a 256 "$TMP/codesign0" | awk '{print tolower($1)}')
  PUBLISHER_JSON=$(python3 -c 'import json,sys; print(json.dumps({"publisherPolicy":"pinnedAppleIdentity","teamIdentifier":sys.argv[1],"leafCertificateSHA256":sys.argv[2]}))' "$TEAM" "$CERT_SHA")
else
  PUBLISHER_JSON='{"publisherPolicy":"integrityOnly","teamIdentifier":null,"leafCertificateSHA256":null}'
fi
python3 - "$OUTPUT" "$RELEASE" "$GENERATION" "$BUNDLE" "$VERSION" "$CDHASH" "$SHA" "$PUBLISHER_JSON" <<'PY'
import json, os, sys, tempfile
out, release, generation, bundle, version, cdhash, sha, publisher = sys.argv[1:]
obj = {"schemaVersion":1,"releaseIdentifier":release,"generation":int(generation),
       "bundleIdentifier":bundle,"helperVersion":version,"helperCDHash":cdhash,
       "helperSHA256":sha, **json.loads(publisher)}
d = os.path.dirname(os.path.abspath(out)) or "."
fd, tmp = tempfile.mkstemp(prefix=".filterkit-trust-", dir=d)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, sort_keys=True, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, out)
    dfd = os.open(d, os.O_RDONLY)
    try: os.fsync(dfd)
    finally: os.close(dfd)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PY
echo "Wrote release trust manifest: $OUTPUT"
echo "CDHash=$CDHASH SHA256=$SHA"
[[ "$POLICY" == "--pin-publisher" ]] && echo "TeamIdentifier=$TEAM LeafCertificateSHA256=$CERT_SHA" || true
