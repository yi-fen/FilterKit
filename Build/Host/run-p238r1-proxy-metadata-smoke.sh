#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/Environment/LaunchServicesAppDiscoveryProvider.swift').read_text()
tests = Path('Tests/UnitTests/AppDiscoveryTests.swift').read_text()
checks = {
    'Bundle ID and Bundle URL remain required LaunchServices proxy fields': 'stringValue("applicationIdentifier", on: proxy)' in source and 'urlValue("bundleURL", on: proxy)' in source,
    'Proxy metadata resolved field-by-field': 'resolveProxyMetadata(proxy: proxy, bundleURL: bundleURL)' in source,
    'Info.plist fallback is a single conditional read': 'let plist = needsPlist ? readPlist(bundleURL) : [:]' in source,
    'Executable name falls back to CFBundleExecutable': 'proxyExecutable ?? (plist["CFBundleExecutable"] as? String)' in source,
    'Path-first classification remains unchanged': 'classify(applicationType: nil, bundleID: bundleID, tags: nil, bundleURL: bundleURL)' in source and 'path.hasPrefix("/Applications/") || path.hasPrefix("/System/")' in source,
    'Proxy-missing executable fallback test exists': 'MetadataProxyMissingExecutableStub' in tests and 'XCTAssertEqual(result.executableName, "ExampleBinary")' in tests,
    'All-proxy-fields-present no-plist test exists': 'testProxyMetadataAvoidsPlistWhenEveryProxyFieldIsPresent' in tests,
    'R1 local diagnostics are emitted': '[FilterKit][AppDiscovery][R4]' in source and 'executable_rate=%d%%' in source,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' | ' + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f'P2-38-R1 proxy metadata audit: {sum(checks.values())}/{len(checks)}')
PY
