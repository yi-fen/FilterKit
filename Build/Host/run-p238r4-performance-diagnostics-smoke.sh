#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
python3 - <<'PY'
from pathlib import Path
provider = Path('Sources/Environment/LaunchServicesAppDiscoveryProvider.swift').read_text()
diag = Path('Sources/Environment/AppDiscoveryPerformanceDiagnostics.swift').read_text()
cache = Path('Sources/Features/Apps/AppIconImageCache.swift').read_text()
view = Path('Sources/Features/Apps/ApplicationIconView.swift').read_text()
apps = Path('Sources/Features/Apps/AppsView.swift').read_text()
tests = Path('Tests/UnitTests/AppDiscoveryTests.swift').read_text()
checks = {
 'LaunchServices total scan timing starts before enumeration': 'let totalScanStartedAt = Date()' in provider and 'timeIntervalSince(totalScanStartedAt)' in provider,
 'Proxy selector calls and per-selector hits are counted': 'recordProxy(selector: selectorName, hit:' in provider and 'proxy_methods={%@}' in diag,
 'Bundle ID and bundle URL proxy methods are included': 'stringValue("applicationIdentifier", on: proxy)' in provider and 'urlValue("bundleURL", on: proxy)' in provider,
 'Info.plist physical read count is instrumented': 'recordInfoPlistRead()' in provider and 'plistReadCount' in diag,
 'Executable completeness remains in inventory summary': 'executable_complete=%d/%d' in provider and 'executable_rate=%d%%' in provider,
 'Icon cache records both hit and miss': 'recordCacheHit()' in cache and 'recordCacheMiss()' in cache,
 'Private API effective success is distinct from empty/unavailable/exception': all(x in cache for x in ['privateAPISuccess', 'privateAPIEmpty', 'privateAPIUnavailable', 'privateAPIExceptions']),
 'Icon file and Asset Bundle reads are counted': 'recordIconFileRead()' in view and 'recordIconAssetRead()' in view,
 'Second APP entry file reads are explicitly counted': 'secondEntryIconFileReads' in diag and 'if pageEntries == 2' in diag,
 'APP page entry and warm inventory are measured': 'recordAppPageEntry(warmInventory:' in apps and 'warmInventoryEntries' in diag,
 'APP page reuses plugin snapshot with hit/miss metrics': 'recordPluginSnapshot(hit: false)' in apps and 'recordPluginSnapshot(hit: true)' in apps,
 'Diagnostics are process-local with no persistence/upload': 'No persistence or upload' in diag and 'UserDefaults' not in diag and 'URLSession' not in diag,
 'R4 output is Debug-only': '#if DEBUG' in diag and '#if DEBUG' in cache,
 'Diagnostics counter regression test exists': 'testR4PerformanceDiagnosticsTrackSelectorHitsAndSecondEntryFileReads' in tests,
}
for label, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' | ' + label)
print(f'P2-38-R4 performance audit: {sum(checks.values())}/{len(checks)}')
if not all(checks.values()): raise SystemExit(1)
PY
