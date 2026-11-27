# P2-39-R1 — Scan Reduction Before Runtime Acceptance

## Scope

This change set reduces repeated filesystem work before proceeding to Apple-device runtime acceptance. It does not add a new scanner, cache layer, TTL, or persistent inventory.

## Changes

1. **Reuse directory assessment listings.** `PluginDirectoryLocator` already enumerates each candidate directory to determine whether it is populated. The diagnostic-only ElleKit component directory is no longer enumerated. For third-party candidates, the resulting entry names are now carried in `PluginDirectoryCandidate.entryNames`; `ReadOnlyPluginScanner` consumes that exact listing rather than enumerating the same directory a second time. Manually constructed assessments without a listing retain a compatibility fallback.
2. **Separate Helper attestation retries from inventory scans.** Expired attestations with unchanged file observations are re-attested using existing hashes and file observations. Helper-unavailable retries also reuse the existing `PluginScanResult`. Only changed file observations trigger a new inventory scan so hashes and Mach-O/plist metadata can be refreshed.
3. **Avoid repeated environment assessment for attestation.** The resolved jailbreak root path from the inventory assessment is passed into `HelperPluginIdentityAttestationService`; the service no longer independently rebuilds `ReadOnlyEnvironmentProvider.makeDiagnosticReport()` on each retry.
4. **Decouple inventory completion from Helper IPC.** The inventory snapshot is published and the inventory in-flight slot is released before Helper attestation begins. Attestation has its own in-flight guard and queues the newest generation if another inventory completes during an older IPC.
5. **Keep App association a pure snapshot join.** If App inventory is not ready, association matching defers instead of invoking another LaunchServices enumeration. It resumes when the App inventory load completes.
6. **Add local counters.** Directory enumerations, assessment-listing reuse, attestation-only retries, and file-change-driven inventory refreshes are counted separately in process-local Debug diagnostics.

## Preserved constraints

- `PluginScanRegistry.shared` remains the only plugin inventory scan entry point.
- `inFlight`, generation protection, successful snapshot retention, existing App inventory TTL/mirror/prewarm behavior remain intact.
- No third scanner, extra TTL, disk inventory cache, bulk icon decode, or production write gate change.
- Attestation remains fail-closed and separate from directory scan timing.

## Validation

- `swiftc -parse` over Sources, App, HelperRuntime, and UnitTests.
- `Build/Host/run-p239r1-scan-reduction-acceptance.sh` static acceptance checks.
- XCTest regression source added for directory-listing reuse. Actual XCTest execution and Apple SDK/device validation require macOS/Xcode and a RootHide device.
