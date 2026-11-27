#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
python3 - <<'PY'
from pathlib import Path
apps = Path('Sources/Features/Apps/AppsView.swift').read_text()
registry = Path('Sources/Environment/PluginScanRegistry.swift').read_text()
locator = Path('Sources/Environment/PluginDirectoryLocator.swift').read_text()
scanner = Path('Sources/Environment/ReadOnlyPluginScanner.swift').read_text()
model = Path('Sources/Environment/Models/PluginDirectoryDiagnostics.swift').read_text()
service = Path('Sources/Features/Apps/HelperPluginIdentityAttestationService.swift').read_text()
diag = Path('Sources/Environment/PluginInventoryPerformanceDiagnostics.swift').read_text()
locator_tests = Path('Tests/UnitTests/PluginDirectoryLocatorTests.swift').read_text()
checks = {
    'APP association consumes PluginScanRegistry snapshot': 'guard let scan = registry.result' in apps,
    'APP association does not instantiate a plugin scanner': 'ReadOnlyPluginScanner(' not in apps,
    'APP association does not rebuild environment assessment': 'makeDiagnosticReport()' not in apps,
    'APP association defers without App snapshot instead of starting another App scan': 'guard let snapshot = await appProvider.currentSnapshot() else' in apps and 'recordAssociationDeferredForAppSnapshot()' in apps,
    'Successful plugin snapshot prevents navigation-triggered scan': 'guard result == nil, inFlight == nil else { return }' in registry,
    'Directory assessment carries enumerated entry names': 'var entryNames: [String]? = nil' in model and 'entryNames: entries' in locator,
    'Diagnostic-only ElleKit component directory is not enumerated': 'role == .thirdPartyPluginDirectory' in locator and 'testElleKitComponentDirectoryIsNotEnumerated' in locator_tests,
    'Scanner reuses assessed directory entries': 'assessedEntries[directoryURL.path]' in scanner and 'recordDirectoryListingReuse()' in scanner,
    'Scanner fallback enumeration is only for external assessments': 'recordDirectoryEnumeration()' in scanner and 'contentsOfDirectory(atPath: directoryURL.path)' in scanner,
    'Attestation retry uses current snapshot, not inventory refresh': 'retryAttestationFromCurrentSnapshot()' in registry and 'hasUnattestedCandidate && now.timeIntervalSince(lastHelperAttestationAttemptAt) >= 30' in registry,
    'Only file changes trigger inventory refresh': 'if !filesUnchanged' in registry and 'if inventoryMustRefresh {\n            PluginInventoryPerformanceDiagnostics.recordInventoryRefreshForChangedFiles()\n            refresh()' in registry,
    'Attestation reuses resolved root path from inventory assessment': 'production(resolvedRootPath: resolvedRootPath)' in registry and 'makeDiagnosticReport()' not in service,
    'Attestation has separate in-flight coordination': 'private var attestationInFlight = false' in registry and 'pendingAttestation' in registry,
    'Generation and old-snapshot retention remain in place': 'scanGeneration.isCurrent(generation)' in registry and 'Retain the last successful snapshot on failure.' in registry,
    'Directory enumeration and listing reuse have separate counters': 'directoryEnumerationCount' in diag and 'directoryListingReuseCount' in diag,
    'Attestation-only retries and file-change rescans are separately counted': 'attestationOnlyRetryCount' in diag and 'inventoryRefreshForChangedFilesCount' in diag,
    'Regression test verifies assessment-to-scanner listing reuse': 'testAssessmentCarriesDirectoryEntriesForScannerReuse' in locator_tests and 'Scanner must reuse the assessment listing' in locator_tests,
    'No persistence or upload path added to diagnostics': 'UserDefaults' not in diag and 'URLSession' not in diag,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' | ' + name)
print(f'P2-39-R1 scan-reduction audit: {sum(checks.values())}/{len(checks)}')
if not all(checks.values()): raise SystemExit(1)
PY
