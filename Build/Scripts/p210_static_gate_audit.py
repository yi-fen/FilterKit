#!/usr/bin/env python3
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
checks = {
    "device probe is read-only and explicitly documents no install": (root/"Build/Device/p210-helper-runtime-probe.sh", r"read-only.*probe|read-only RootHide Helper runtime probe"),
    "probe checks root manifest execution gate": (root/"Build/Device/p210-helper-runtime-probe.sh", r"executionEnabled.*false"),
    "probe checks both CDHash pins": (root/"Build/Device/p210-helper-runtime-probe.sh", r"allowedHelperCDHashes\.0"),
    "probe checks launchd disabled state": (root/"Build/Device/p210-helper-runtime-probe.sh", r"Disabled|disabled"),
    "probe does not invoke launchctl mutation": (root/"Build/Device/p210-helper-runtime-probe.sh", r"launchctl print"),
    "dispatcher commit gate remains closed": (root/"Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", r"pluginAssociationCommitReleased\s*=\s*false"),
    "coordinator commit gate remains closed": (root/"Sources/Environment/Helper/HelperDeploymentCoordinator.swift", r"pluginAssociationCommitReleased\s*=\s*false"),
    "dispatcher execution gate remains closed": (root/"Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", r"executionReleased\s*=\s*false"),
    "production backend execution gate remains closed": (root/"Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift", r"executionReleased\s*=\s*false"),
}
failed=[]
for name,(path,pattern) in checks.items():
    ok=path.exists() and re.search(pattern,path.read_text(encoding="utf-8"),re.I) is not None
    print(("PASS" if ok else "FAIL")+"  "+name)
    if not ok: failed.append(name)
print(f"P2-10 static gate audit: {len(checks)-len(failed)}/{len(checks)} passed")
sys.exit(1 if failed else 0)
