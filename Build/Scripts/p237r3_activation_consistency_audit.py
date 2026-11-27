#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(name, ok):
    checks.append((name, bool(ok)))
def read(path):
    return (ROOT / path).read_text()

scan_model = read('Sources/Core/Models/PluginScanModels.swift')
scanner = read('Sources/Environment/ReadOnlyPluginScanner.swift')
attestation = read('Sources/Core/Models/Helper/HelperPluginIdentityAttestationModels.swift')
identity = read('Sources/Core/Models/PluginIdentityVerificationResult.swift')
resolver = read('Sources/Environment/Deployment/AppPluginActivationStateResolver.swift')
registry = read('Sources/Environment/PluginScanRegistry.swift')
ledger = read('Sources/Core/Models/AppPluginActivationPreviewLedger.swift')
apps = read('Sources/Features/Apps/AppsView.swift')
coordinator = read('Sources/Environment/Helper/HelperDeploymentCoordinator.swift')
dispatcher = read('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift')
preflight = read('Sources/Environment/Deployment/PluginActivationPreflight.swift')
gate = read('Sources/Environment/Deployment/PluginToggleReleaseGate.swift')
en = read('Resources/en.lproj/Localizable.strings')
zh = read('Resources/zh-Hans.lproj/Localizable.strings')

check('scan model stores exact manifest hash', 'var manifestSHA256: String? = nil' in scan_model)
check('scan model stores file metadata observations for all three artifacts', all(x in scan_model for x in ['dylibFileObservation', 'plistFileObservation', 'manifestFileObservation']))
check('scanner hashes the same manifest bytes used to decode association metadata', 'manifestData = readManifestData(from: manifest)' in scanner and 'manifestHash = manifestData.map(SHA256Digest.hex)' in scanner and 'JSONDecoder().decode(FilterKitPluginManifest.self, from: manifestData)' in scanner)
check('scanner detects concurrent dylib and plist replacement during read', scanner.count('Self.fileObservation(afterAttributes) ==') >= 2)
check('scanner detects concurrent manifest replacement during read', 'beforeObservation != afterObservation' in scanner)
check('attestation has bounded freshness window', 'static let maximumAge: TimeInterval = 120' in attestation and 'age >= -5 && age <= maximumAge' in attestation)
check('activation resolver rejects expired Helper attestation', 'attestation.isFresh(now: now, maximumAge: maximumAttestationAge)' in identity and 'activation_helper_attestation_expired' in identity)
check('identity proof binds manifest, dylib, plist and Mach-O hashes', all(x in identity for x in ['attestation.manifestSHA256?.caseInsensitiveCompare', 'attestation.dylibSHA256?.caseInsensitiveCompare', 'attestation.plistSHA256?.caseInsensitiveCompare', 'attestation.machOIdentitySHA256?.caseInsensitiveCompare']))
check('package-manager-owned plugins are explicitly rejected', 'plugin.ownership == .packageManager' in identity)
check('unknown scanner ownership requires a Helper attestation', 'guard let attestation = plugin.helperIdentityAttestation' in identity and 'attestation.isVerified' in identity)
check('complete soft-association set is compared to Filter.Bundles', 'associationsMatchFilter' in identity and 'actual.intersection(enabledSoft) == enabledSoft' in identity)
check('disabled soft associations cannot remain in Filter.Bundles', 'actual.isDisjoint(with: disabledSoft)' in identity)
check('undeclared Filter bundle targets are rejected', 'actual.isSubset(of: allowed)' in identity)
check('hard binding remains permanent while its activation can be off', 'case .hardBound, .filterMatched:' in resolver and 'observed = filterListsTarget ? .enabled : .disabled' in resolver)
check('global and alternate filter dimensions remain un-attributable', 'globalFilterCannotBeScoped' in resolver and 'alternateMatchDimensionsPresent' in resolver)
check('fresh Helper evidence is authoritative; stale evidence is display-only', 'identityEvidence.permitsActivationPreview' in resolver and 'plugin.filterConfiguration' in resolver)
check('registry expires attestations and clears the old snapshot before refresh', 'expireStaleAttestationsAndRefreshIfNeeded' in registry and 'helperIdentityAttestation = nil' in registry and 'snapshotRevision &+= 1' in registry and 'refresh()' in registry)
check('registry invalidates when file metadata changes', all(x in registry for x in ['fileObservationMatches(item.dylibPath', 'fileObservationMatches(item.plistPath', 'fileObservationMatches(item.manifestPath']))
check('registry retries only transient Helper-unavailable results at a bounded interval', 'lastHelperAttestationAttemptAt' in registry and 'timeIntervalSince(lastHelperAttestationAttemptAt) >= 30' in registry and 'attestation.status != .unavailable' in registry)
check('definitive Helper rejection is retained and not auto-retried as a success candidate', 'attestation.status == .verified' in registry and 'attestation.status != .unavailable' in registry)
check('preview state is isolated by Plugin ID and target App', '"\\(pluginID)::\\(bundleID)"' in ledger)
check('new scan snapshot clears legacy preview ledger state', 'values.removeAll()' in ledger and 'func updateSnapshot' in ledger)
check('APP detail now uses the R7 Prepare/Commit operation store', 'operationStore.prepare(plugin: plugin' in apps and 'operationStore.commit(userConfirmed: true' in apps and 'invalidatePending' in apps)
check('Helper and App mutation release gates remain closed', 'static let pluginAssociationCommitReleased = false' in coordinator and 'static let pluginAssociationCommitReleased = false' in dispatcher and 'static let productionMutationReleased = false' in gate and 'static let mutationReleaseEnabled = false' in preflight)
check('attestation-expired message exists in English and Chinese', 'apps.detail.activation_helper_attestation_expired' in en and 'apps.detail.activation_helper_attestation_expired' in zh)

for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
failed = [name for name, ok in checks if not ok]
print(f'P2-37-R3 activation consistency audit: {len(checks)-len(failed)}/{len(checks)}')
if failed:
    sys.exit(1)
