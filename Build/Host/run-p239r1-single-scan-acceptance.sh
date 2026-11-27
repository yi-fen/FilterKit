#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
python3 - <<'PY'
from pathlib import Path
apps = Path('Sources/Features/Apps/AppsView.swift').read_text()
registry = Path('Sources/Environment/PluginScanRegistry.swift').read_text()
reader = Path('Sources/Environment/ReadOnlyPluginAssociationReader.swift').read_text()
diag = Path('Sources/Environment/PluginInventoryPerformanceDiagnostics.swift').read_text()
tests = Path('Tests/UnitTests/AppDiscoveryTests.swift').read_text()
checks = {
    'APP association consumes PluginScanRegistry.shared.result': 'let registry = PluginScanRegistry.shared' in apps and 'guard let scan = registry.result' in apps,
    'APP association never constructs ReadOnlyPluginScanner': 'ReadOnlyPluginScanner(' not in apps,
    'APP association never rebuilds environment diagnostic report': 'makeDiagnosticReport()' not in apps,
    'Only PluginScanRegistry starts scanner inventory work': 'ReadOnlyPluginScanner' in registry and 'scanPlugins()' in registry and 'ReadOnlyPluginScanner' not in apps,
    'loadIfNeeded does not rescan when a successful snapshot exists': 'guard result == nil, inFlight == nil else { return }' in registry,
    'Association reader accepts an injected app snapshot': 'snapshotApps: [InstalledApp]?' in reader and 'if let snapshotApps' in reader,
    'Registry scan count is instrumented at the single scan entry': 'recordInventoryScanStarted()' in registry,
    'Environment assessment timing is distinct': 'recordEnvironmentAssessment' in registry and 'environment_assessment_ms' in diag,
    'Plugin directory scan timing is distinct': 'recordPluginDirectoryScan' in registry and 'plugin_directory_scan_ms' in diag,
    'Helper attestation timing is distinct from directory scan': 'recordAttestation' in registry and 'attestation_ms' in diag,
    'Attestation outcomes are separately counted': all(x in diag for x in ['attestationVerified', 'attestationUnavailable', 'attestationRejected', 'attestationErrors']),
    'Association snapshot reuse is counted and missing App inventory is deferred': 'recordAssociationSnapshotConsumption()' in apps and 'recordAssociationDeferredForAppSnapshot()' in apps,
    'Diagnostics remain process-local and Debug-only': '#if DEBUG' in diag and 'UserDefaults' not in diag and 'URLSession' not in diag,
    'R1 regression test covers separated timing and snapshot consumption': 'testP239R1SeparatesPluginInventoryFromAttestationAndTracksSnapshotReuse' in tests,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' | ' + name)
print(f'P2-39-R1 single-scan audit: {sum(checks.values())}/{len(checks)}')
if not all(checks.values()): raise SystemExit(1)
PY
