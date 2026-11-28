#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
script = (ROOT / 'Build/scripts/p245_r4_1_apple_build_signing_closure.sh').read_text()
project = (ROOT / 'Project.yml').read_text()
provider = (ROOT / 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
trust = (ROOT / 'Sources/Core/Models/Helper/HelperTrustProvisioning.swift').read_text()
plist = (ROOT / 'Build/Helper/cn.yfen.filterkit.helper.plist.template').read_text()
checks = [
 ('R4.1 is macOS-only', 'uname -s' in script and 'Darwin' in script),
 ('requires explicit Apple signing identity', 'FILTERKIT_CODESIGN_IDENTITY:?' in script),
 ('requires explicit Team ID', 'FILTERKIT_EXPECTED_TEAM_ID:?' in script),
 ('requires installable App provisioning profile', 'FILTERKIT_PROVISIONING_PROFILE_SPECIFIER:?' in script),
 ('requires monotonic trust generation', 'FILTERKIT_TRUST_GENERATION:?' in script),
 ('builds standalone Helper for iPhoneOS', '-target FilterKitHelper -sdk iphoneos' in script),
 ('signs Helper with explicit identifier', '--identifier cn.yfen.filterkit.helper' in script),
 ('verifies Helper Team ID and CDHash', 'TeamIdentifier=$FILTERKIT_EXPECTED_TEAM_ID' in script and 'Helper CDHash unavailable' in script),
 ('pins final Helper CDHash into App trust JSON', 'allowedHelperCDHashes' in script and 'FilterKit-Helper-AppTrust.json' in script),
 ('signs App with same identity and Team ID', 'CODE_SIGN_IDENTITY="$FILTERKIT_CODESIGN_IDENTITY"' in script and 'DEVELOPMENT_TEAM="$FILTERKIT_EXPECTED_TEAM_ID"' in script),
 ('verifies App signature and Team ID', 'codesign --verify --deep --strict' in script and 'App TeamIdentifier mismatch' in script),
 ('verifies embedded provisioning profile', 'security cms -D -i' in script and 'profile TeamIdentifier mismatch' in script),
 ('no install or launchd bootstrap commands', all(x not in script for x in ['launchctl', 'ideviceinstaller', 'bootstrap ', 'bootout '])),
 ('no production gate is opened', 'executionReleased = true' not in script and 'executionEnabled=true' not in script),
 ('Helper target remains explicitly unsigned at Xcode build stage', 'CODE_SIGNING_ALLOWED: NO' in project),
 ('Helper identity requires signed Team entitlement evidence', 'SecTaskCopyValueForEntitlement' in provider and 'teamIdentifierUnavailable' in provider),
 ('peer identity binding requires Bundle ID and Team ID', 'verifiedCodeIdentifier' in (ROOT/'Sources/Environment/Helper/Transport/HelperCodeSigningIdentityBindingPolicy.swift').read_text() and 'verifiedTeamIdentifier' in (ROOT/'Sources/Environment/Helper/Transport/HelperCodeSigningIdentityBindingPolicy.swift').read_text()),
 ('App trust schema pins Helper CDHash', 'allowedHelperCDHashes' in trust and 'HelperTrustPinSet.validatePins' in trust),
 ('launchd template remains disabled', '<key>Disabled</key>\n    <true/>' in plist and '<key>RunAtLoad</key>\n    <false/>' in plist),
 ('build operates on isolated source copy', 'rsync -a --delete' in script and '"$SRC/"' in script),
 ('artifact hashes are recorded', 'shasum -a 256' in script),
]
failed=[]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok: failed.append(name)
print(f'P2-45-R4.1 static audit: {len(checks)-len(failed)}/{len(checks)} passed')
if failed: sys.exit(1)
