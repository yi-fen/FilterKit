# P2-38-R2 — App Icon Loading Optimization

## Scope

- Resolve icons lazily from `ApplicationIconView` when a visible row appears.
- Attempt the Bundle-ID LaunchServices/UIKit private lookup first.
- Fall back to bundle file candidates, Asset Bundle lookup, then embedded icon data.
- Store every decoded source in one process-wide `NSCache`.
- Include both Bundle ID and display scale in the cache key.
- Keep inventory discovery read-only; no icon decoding is performed by discovery scanners.

## Private API outcome semantics

`FKLookupApplicationIcon` reports four distinct outcomes:

- `success`: a non-nil `UIImage` with finite, positive dimensions was returned.
- `emptyImage`: the private selector returned nil or an unusable image.
- `unavailable`: the selector is not present, or Objective-C runtime access is unavailable.
- `exception`: an Objective-C exception was caught around the private invocation.

The Objective-C wrapper exists specifically because Swift `do/catch` cannot catch `NSException`.

## Local diagnostics

Debug builds emit a throttled, local-only `[FilterKit][AppIcon][R2]` line at most once per 30 seconds. It reports cache hit rate and private API effective-image success rate, with success, empty, unavailable, and exception counts. No diagnostic data is uploaded.

## Validation performed in this environment

- `swiftc -parse` over project Swift sources and unit-test sources: passed.
- P2-38-R2 source audit: 10/10 passed.
- P2-38-R1 regression audit: 8/8 passed.
- Scale-specific cache-key unit test added.

## Not performed

This Linux environment has no Xcode, Apple SDK, UIKit runtime, or iOS device. Therefore Objective-C/UIKit compilation, XCTest execution, private selector behavior, actual icon hit rates, and RootHide device acceptance remain pending on macOS/device. Static parsing is not an Apple-platform build.
