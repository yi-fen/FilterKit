#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
verify = (ROOT/'Build/scripts/p245_r4_2_verify_signed_artifacts.sh').read_text()
probe = (ROOT/'Build/scripts/p245_r4_2_device_runtime_probe.sh').read_text()
provider = (ROOT/'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
project = (ROOT/'Project.yml').read_text()
helper_plist = (ROOT/'Build/Helper/cn.yfen.filterkit.helper.plist.template').read_text()
gates = [
 ('artifact verifier is macOS-only', 'uname -s' in verify and 'Darwin' in verify),
 ('verifies standalone Helper code signature', 'codesign --verify --strict' in verify),
 ('verifies App code signature recursively', 'codesign --verify --deep --strict' in verify),
 ('checks App Bundle ID', "aps['Identifier'] == 'cn.yfen.filterkit'" in verify),
 ('checks Helper Bundle ID', "hs['Identifier'] == 'cn.yfen.filterkit.helper'" in verify),
 ('requires same expected Team ID', "hs['TeamIdentifier'] == team and aps['TeamIdentifier'] == team" in verify),
 ('validates Helper CDHash format', "re.fullmatch(r'[0-9a-fA-F]{40}', hs['CDHash'])" in verify),
 ('validates App CDHash format', "re.fullmatch(r'[0-9a-fA-F]{40}', aps['CDHash'])" in verify),
 ('cross-checks exact Helper CDHash against embedded trust', "hs['CDHash'].lower() in allowed" in verify),
 ('checks trust generation', "str(t.get('generation')) == generation" in verify),
 ('checks Helper UID/GID scope', "t.get('allowedHelperUIDs') == [0]" in verify),
 ('decodes and validates provisioning profile', 'security cms -D -i' in verify and 'profile Team ID mismatch' in verify),
 ('writes artifact hashes', 'shasum -a 256' in verify),
 ('does not install or bootstrap', not any(line.lstrip().startswith(('launchctl ', 'ideviceinstaller ')) for line in verify.splitlines())),
 ('device probe is Darwin-only and root-authorized', 'uname -s' in probe and 'id -u' in probe),
 ('device probe requires explicit JBROOT/helper/socket/label', all(x in probe for x in ('FILTERKIT_JBROOT:', 'FILTERKIT_HELPER_BIN:', 'FILTERKIT_SOCKET_PATH:', 'FILTERKIT_LAUNCHD_LABEL:'))),
 ('device probe refuses report inside JBROOT', 'case "$FILTERKIT_REPORT" in "$FILTERKIT_JBROOT"/*)' in probe),
 ('device probe does not bootstrap/bootout/kickstart', not any(line.lstrip().startswith(('launchctl bootstrap', 'launchctl bootout', 'launchctl kickstart')) for line in probe.splitlines())),
 ('peer Team ID remains OS-derived from Audit Token task', 'SecTaskCreateWithAuditToken' in provider and 'SecTaskCopyValueForEntitlement' in provider),
 ('Helper launchd template remains disabled', '<key>Disabled</key>\n    <true/>' in helper_plist and '<key>RunAtLoad</key>\n    <false/>' in helper_plist),
 ('Helper Xcode signing gate remains unchanged/closed', 'CODE_SIGNING_ALLOWED: NO' in project),
 ('all production execution gates remain false', all('executionReleased = false' in (ROOT/p).read_text() for p in ['Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','Sources/Environment/Helper/HelperDeploymentCoordinator.swift','Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift'])),
]
failed=[]
for name, ok in gates:
 print(('PASS ' if ok else 'FAIL ')+name)
 if not ok: failed.append(name)
print(f'P2-45-R4.2 static audit: {len(gates)-len(failed)}/{len(gates)} passed')
if failed: sys.exit(1)
