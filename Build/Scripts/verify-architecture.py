#!/usr/bin/env python3
from pathlib import Path
import sys
import re

ROOT = Path(__file__).resolve().parents[2]
required = [
    "Sources/Core/Models/InstalledApp.swift",
    "Sources/Core/Models/PluginModels.swift",
    "Sources/Core/Protocols/ServiceProtocols.swift",
    "Sources/Environment/Profiles/ElleKitProfile.swift",
    "Sources/Core/StorageManagement/StorageModels.swift",
    "Sources/Persistence/PersistenceBoundary.swift",
    "Sources/Localization/LocalizationBoundary.swift",
    "Build/P0-06-ARCHITECTURE.md",
]
missing = [p for p in required if not (ROOT / p).is_file()]
if missing:
    print("Missing architecture files:")
    print("\n".join(missing))
    sys.exit(1)

# Guard against accidentally adding destructive/privileged implementation in this phase.
forbidden_patterns = [(r"\bProcess\s*\(", "Process()"), (r"/usr/bin/", "/usr/bin/"), (r"\bposix_spawn\s*\(", "posix_spawn()" )]
violations = []
for path in (ROOT / "Sources").rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    for pattern, label in forbidden_patterns:
        if re.search(pattern, text):
            violations.append(f"{path.relative_to(ROOT)}: {label}")
if violations:
    print("Unexpected command/privilege primitives found:")
    print("\n".join(violations))
    sys.exit(1)

print(f"Architecture structure check passed ({len(required)} required files).")
