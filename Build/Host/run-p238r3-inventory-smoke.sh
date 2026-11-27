#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
cache = (root/'Sources/Environment/CachedAppDiscoveryProvider.swift').read_text()
apps = (root/'Sources/Features/Apps/AppsView.swift').read_text()
observer = (root/'Sources/Environment/LaunchServicesApplicationsChangeObserver.swift').read_text()
registry = (root/'Sources/Environment/PluginScanRegistry.swift').read_text()
tests = (root/'Tests/UnitTests/AppDiscoveryTests.swift').read_text()
checks = {
  'stale refresh preserves snapshot': 'markStaleAndRefresh()' in cache and 'mirror = nil' not in cache[cache.index('func markStaleAndRefresh'):cache.index('func currentSnapshot')],
  'successful refresh atomically replaces mirror': 'mirror = sorted' in cache and 'isStale = false' in cache,
  'failed refresh retains stale state for retry': 'guard case .success(let apps) = result else { return }' in cache,
  'Apps reuses PluginScanRegistry result': 'PluginScanRegistry.shared' in apps and 'registry.result' in apps,
  'Apps no longer creates a second plugin scanner': 'ReadOnlyPluginScanner(' not in apps,
  'global LaunchServices observer is process scoped': 'private static let changeObserver' in cache,
  'notify cancellation on teardown': 'notify_cancel(token)' in observer,
  '0.5 second notification debounce': 'queue.asyncAfter(deadline: .now() + 0.5' in observer,
  'observer triggers stale refresh': 'shared.markStaleAndRefresh()' in cache,
  'successful inventory refresh publishes atomic UI replacement': 'filterKitAppInventoryDidRefresh' in cache and 'filterKitAppInventoryDidRefresh' in apps and 'self?.apps = refreshedApps' in apps,
  'stale refresh success/failure tests added': 'testStaleRefreshKeepsOldSnapshotUntilSuccessfulReplacement' in tests and 'testFailedStaleRefreshRetainsLastSuccessfulSnapshotAndRetries' in tests,
  'PluginScanRegistry existing scan lifecycle preserved': 'scanGeneration.begin()' in registry and 'self.result = output.result' in registry,
}
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'P2-38-R3 inventory audit: {sum(checks.values())}/{len(checks)}')
if not all(checks.values()): raise SystemExit(1)
PY
swiftc -parse "$ROOT/Sources/Environment/CachedAppDiscoveryProvider.swift" "$ROOT/Sources/Environment/LaunchServicesApplicationsChangeObserver.swift" "$ROOT/Sources/Features/Apps/AppsView.swift" "$ROOT/Tests/UnitTests/AppDiscoveryTests.swift"
echo 'Swift syntax parse: PASS'
