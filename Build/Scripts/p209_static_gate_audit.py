#!/usr/bin/env python3
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
checks = {
 "dispatcher commit gate closed": (root/"Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", r"pluginAssociationCommitReleased\s*=\s*false"),
 "coordinator commit gate closed": (root/"Sources/Environment/Helper/HelperDeploymentCoordinator.swift", r"pluginAssociationCommitReleased\s*=\s*false"),
 "dispatcher deployment gate closed": (root/"Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", r"executionReleased\s*=\s*false"),
 "deployment coordinator gate closed": (root/"Sources/Environment/Helper/HelperDeploymentCoordinator.swift", r"executionReleased\s*=\s*false"),
 "production backend gate closed": (root/"Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift", r"executionReleased\s*=\s*false"),
 "two-pass provisioning tool present": (root/"Build/scripts/p209_provision_helper_trust.py", r"sub\.add_parser\(\"prepare\""),
 "finalizer emits disabled root manifest": (root/"Build/scripts/p209_provision_helper_trust.py", r'"executionEnabled": False'),
 "launchd remains disabled": (root/"Build/scripts/p209_provision_helper_trust.py", r'"Disabled": True'),
}
failed=[]
for name,(path,pattern) in checks.items():
    ok=path.exists() and re.search(pattern,path.read_text(encoding="utf-8")) is not None
    print(("PASS" if ok else "FAIL")+"  "+name)
    if not ok: failed.append(name)
print(f"P2-09 static gate audit: {len(checks)-len(failed)}/{len(checks)} passed")
sys.exit(1 if failed else 0)
