#!/usr/bin/env bash
# P2-45-R4.2: verify already-built App + standalone Helper artifacts on macOS.
# Read-only with respect to the supplied artifacts; no install, launchctl, or write-gate changes.
set -euo pipefail
fail(){ echo "FAIL: $*" >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || fail "requires macOS codesign/security/plutil"
for t in codesign security plutil python3 shasum; do command -v "$t" >/dev/null || fail "missing $t"; done
: "${FILTERKIT_APP_PATH:?Set path to signed FilterKit.app}"
: "${FILTERKIT_HELPER_PATH:?Set path to separately signed filterkit-helper}"
: "${FILTERKIT_EXPECTED_TEAM_ID:?Set expected 10-character Team ID}"
: "${FILTERKIT_EXPECTED_TRUST_GENERATION:?Set expected trust generation}"
APP="$FILTERKIT_APP_PATH"; HELPER="$FILTERKIT_HELPER_PATH"
[[ -d "$APP" ]] || fail "App bundle not found"
[[ -f "$HELPER" ]] || fail "Helper executable not found"
[[ "$FILTERKIT_EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "invalid Team ID"
[[ "$FILTERKIT_EXPECTED_TRUST_GENERATION" =~ ^[1-9][0-9]*$ ]] || fail "invalid trust generation"
TRUST="$APP/FilterKit-Helper-AppTrust.json"
PROFILE="$APP/embedded.mobileprovision"
[[ -f "$TRUST" ]] || fail "embedded Helper trust JSON missing"
[[ -f "$PROFILE" ]] || fail "embedded provisioning profile missing"
OUT="${FILTERKIT_R4_2_REPORT:-$PWD/FilterKit-R4.2-SignedArtifact-Report}"
mkdir -p "$OUT"

codesign --verify --strict --verbose=2 "$HELPER" >"$OUT/Helper-verify.txt" 2>&1 || fail "Helper signature verification failed"
codesign --verify --deep --strict --verbose=2 "$APP" >"$OUT/App-verify.txt" 2>&1 || fail "App signature verification failed"
codesign -dv --verbose=4 "$HELPER" 2>"$OUT/Helper-signature.txt"
codesign -dv --verbose=4 "$APP" 2>"$OUT/App-signature.txt"
security cms -D -i "$PROFILE" > "$OUT/App-profile.plist" || fail "profile CMS decode failed"
plutil -lint "$OUT/App-profile.plist" >/dev/null || fail "profile plist invalid"
python3 - "$APP" "$HELPER" "$TRUST" "$OUT/App-profile.plist" "$FILTERKIT_EXPECTED_TEAM_ID" "$FILTERKIT_EXPECTED_TRUST_GENERATION" "$OUT/Helper-signature.txt" "$OUT/App-signature.txt" <<'PY'
import json, plistlib, pathlib, re, sys
app, helper, trust_path, profile_path, team, generation, helper_sig_path, app_sig_path = sys.argv[1:]
def sig(path):
    text = pathlib.Path(path).read_text(errors='replace')
    def get(key):
        m = re.search(r'^'+re.escape(key)+r'=(.*)$', text, re.M)
        return m.group(1).strip() if m else None
    return {k:get(k) for k in ('Identifier','TeamIdentifier','CDHash')}
hs, aps = sig(helper_sig_path), sig(app_sig_path)
assert hs['Identifier'] == 'cn.yfen.filterkit.helper', f"Helper identifier mismatch: {hs}"
assert aps['Identifier'] == 'cn.yfen.filterkit', f"App identifier mismatch: {aps}"
assert hs['TeamIdentifier'] == team and aps['TeamIdentifier'] == team, 'App/Helper TeamIdentifier mismatch'
assert hs['CDHash'] and re.fullmatch(r'[0-9a-fA-F]{40}', hs['CDHash']), 'Helper CDHash missing/invalid'
assert aps['CDHash'] and re.fullmatch(r'[0-9a-fA-F]{40}', aps['CDHash']), 'App CDHash missing/invalid'
t = json.loads(pathlib.Path(trust_path).read_text())
assert t.get('schemaVersion') == 1, 'trust schema version mismatch'
assert t.get('bundleIdentifier') == 'cn.yfen.filterkit', 'trust App Bundle ID mismatch'
assert str(t.get('generation')) == generation, 'trust generation mismatch'
allowed = [str(x).lower() for x in t.get('allowedHelperCDHashes', [])]
assert hs['CDHash'].lower() in allowed, 'embedded trust does not pin this exact Helper CDHash'
assert t.get('allowedHelperUIDs') == [0] and t.get('allowedHelperGIDs') == [0], 'unexpected Helper UID/GID trust scope'
p = plistlib.loads(pathlib.Path(profile_path).read_bytes())
assert team in p.get('TeamIdentifier', []), 'profile Team ID mismatch'
e = p.get('Entitlements', {})
app_id = e.get('application-identifier', '')
assert app_id.endswith('.cn.yfen.filterkit'), f'application-identifier mismatch: {app_id}'
assert p.get('ExpirationDate'), 'profile expiration missing'
print('PASS: App and Helper signature identifiers, Team ID, CDHash, embedded trust pin, generation, UID/GID scope, and provisioning profile agree.')
print('NOTE: This does not prove iOS SecTask entitlement lookup, RootHide launchd, IPC, or filesystem runtime behavior.')
PY
shasum -a 256 "$HELPER" "$TRUST" "$APP/Info.plist" > "$OUT/SHA256.txt"
cat > "$OUT/Artifact-Summary.txt" <<SUMMARY
App: $APP
Helper: $HELPER
Expected Team ID: $FILTERKIT_EXPECTED_TEAM_ID
Expected trust generation: $FILTERKIT_EXPECTED_TRUST_GENERATION
Helper signature: $OUT/Helper-signature.txt
App signature: $OUT/App-signature.txt
Provisioning profile: $OUT/App-profile.plist
Hashes: $OUT/SHA256.txt
SUMMARY
echo "PASS: signed artifact cross-verification completed. Report: $OUT"
echo "NOT DONE: device install, launchd, Helper IPC, SecTask entitlement lookup, APFS, production writes."
