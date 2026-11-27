#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
python3 - <<'PY'
from pathlib import Path
view = Path('Sources/Features/Apps/ApplicationIconView.swift').read_text()
api = Path('Sources/Features/Apps/AppIconPrivateAPI.swift').read_text()
cache = Path('Sources/Features/Apps/AppIconImageCache.swift').read_text()
objc = Path('Sources/Features/Apps/FilterKitAppIconPrivateAPI.m').read_text()
tests = Path('Tests/UnitTests/AppIconDescriptorBuilderTests.swift').read_text()
project = Path('Project.yml').read_text()
checks = {
    'Private API is attempted before file and asset fallbacks': view.index('AppIconPrivateAPI.applicationIcon') < view.index('descriptor.fileCandidates') < view.index('UIImage(named:'),
    'All decoded sources use one process-wide NSCache': 'private static let cache = NSCache<NSString, UIImage>()' in cache and 'AppIconImageCache.store' in view,
    'Cache key includes Bundle ID and scale': '"\\(bundleIdentifier)|scale:\\(scaleToken)"' in cache,
    'Icon load remains lazy on visible SwiftUI row': '.task(id:' in view and 'Task.detached(priority: .utility)' in view,
    'Private API success requires a non-empty image': 'image.size.width <= 0 || image.size.height <= 0' in objc and 'FKApplicationIconLookupStatusSuccess' in objc,
    'Private API unavailable, empty, and exception outcomes are distinct': all(x in api for x in ['.unavailable', '.emptyImage', '.exception', '.success']) and 'FKApplicationIconLookupStatusException' in objc,
    'Objective-C exception is caught around private API call': '@catch (NSException *exception)' in objc,
    'Bridging header is configured for app target': 'SWIFT_OBJC_BRIDGING_HEADER: Sources/Features/Apps/FilterKit-Apps-Bridging-Header.h' in project,
    'Scale-separated cache key unit test exists': 'testDecodedIconCacheKeyIncludesBundleIdentifierAndScale' in tests,
    'No eager icon decode was added to discovery scanners': 'UIImage(contentsOfFile:' not in Path('Sources/Environment/LaunchServicesAppDiscoveryProvider.swift').read_text(),
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' | ' + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f'P2-38-R2 icon loading audit: {sum(checks.values())}/{len(checks)}')
PY
