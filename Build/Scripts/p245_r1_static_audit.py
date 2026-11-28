#!/usr/bin/env python3
"""Static, read-only P2-45-R1 build/signing and write-gate audit."""
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[2]
project = (ROOT / 'Project.yml').read_text()
checks = []
def check(name, ok):
    checks.append((name, bool(ok)))
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

check('App bundle identifier remains cn.yfen.filterkit', bool(re.search(r'PRODUCT_BUNDLE_IDENTIFIER: cn\.yfen\.filterkit$', project, re.M)))
check('Helper bundle identifier remains cn.yfen.filterkit.helper', 'PRODUCT_BUNDLE_IDENTIFIER: cn.yfen.filterkit.helper' in project)
helper = project.split('  FilterKitHelper:', 1)[1].split('  FilterKitTests:', 1)[0]
check('Helper target is currently explicitly unsigned (release blocker)', 'CODE_SIGNING_ALLOWED: NO' in helper)
check('App signing remains Automatic (no hard-coded team)', 'CODE_SIGN_STYLE: Automatic' in project and 'DEVELOPMENT_TEAM:' not in project)

files = {
 'dispatcher execution release gate remains false': ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', r'static let executionReleased = false'),
 'deployment coordinator execution release gate remains false': ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift', r'static let executionReleased = false'),
 'production deployment backend execution release gate remains false': ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift', r'static let executionReleased = false'),
}
for label, (rel, pattern) in files.items():
    text = (ROOT / rel).read_text()
    check(label, bool(re.search(pattern, text)))

dispatch = (ROOT / 'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
check('test-only activation execution injection defaults false', 'activationCommitExecutionEnabled: Bool = false' in dispatch)
check('provisioning model keeps execution disabled', 'executionEnabled: false' in (ROOT / 'Sources/Core/Models/Helper/HelperInstallerProvisioning.swift').read_text())

# R1 is intentionally not a production write enablement stage.
check('R1 preflight script is present', (ROOT / 'Build/scripts/p245_r1_darwin_build_signing_preflight.sh').is_file())
failed = sum(not ok for _, ok in checks)
print(f"P2-45-R1 static audit: {len(checks)-failed}/{len(checks)} passed; {failed} blocker(s)")
# Helper unsigned configuration is an acknowledged blocker, not a test failure.
if failed:
    sys.exit(1)
