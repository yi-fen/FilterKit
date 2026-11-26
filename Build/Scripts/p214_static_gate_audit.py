#!/usr/bin/env python3
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
checks = {
    "commit dispatcher gate remains closed": r"pluginAssociationCommitReleased\s*=\s*false",
    "deployment coordinator commit gate remains closed": r"pluginAssociationCommitReleased\s*=\s*false",
    "general dispatcher execution gate remains closed": r"executionReleased\s*=\s*false",
    "socket node is checked after chmod": r"chmod\(socketPath, socketMode\).*?validateSocketNode\(\)",
    "socket check occurs before listen": r"validateSocketNode\(\).*?listen\(listener",
    "socket node uses lstat": r"lstat\(\$0, &info\)",
    "socket diagnostics are bounded": r"String\(reasonCode\.prefix\(96\)\)",
    "CDHash diagnostics are truncated": r"prefix\(12\)",
    "audit sink receives authentication events": r"diagnosticSink:\s*\{ event in.*?audit\.append",
}
all_text = "\n".join(p.read_text(errors="ignore") for p in (root / "Sources").rglob("*.swift"))
transport = (root / "Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift").read_text()
runtime = (root / "Sources/Environment/Helper/Runtime/HelperRuntime.swift").read_text()
combined = all_text + "\n" + transport + "\n" + runtime
failed = []
for name, pattern in checks.items():
    ok = re.search(pattern, combined, re.S) is not None
    print(("PASS" if ok else "FAIL") + ": " + name)
    if not ok: failed.append(name)
# Check all known production release switches are false in their owning source files.
for rel in [
    "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift",
    "Sources/Environment/Helper/HelperDeploymentCoordinator.swift",
    "Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift",
]:
    p = root / rel
    if not p.exists():
        print("FAIL: missing gate source " + rel); failed.append(rel); continue
    text = p.read_text(errors="ignore")
    if re.search(r"(?:executionReleased|pluginAssociationCommitReleased)\s*=\s*true", text):
        print("FAIL: release gate enabled in " + rel); failed.append(rel)
    else:
        print("PASS: no enabled release gate in " + rel)
sys.exit(1 if failed else 0)
