#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

def read(path):
    return (ROOT / path).read_text()

models = read('Sources/Core/Models/Helper/HelperPluginIdentityAttestationModels.swift')
ipc = read('Sources/Core/Models/Helper/HelperIPCModels.swift')
dispatcher = read('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift')
attestor = read('Sources/Environment/Helper/Execution/HelperPluginIdentityAttestor.swift')
verifier = read('Sources/Environment/Helper/Execution/HelperOwnershipProofVerifier.swift')
proof = read('Sources/Environment/Helper/Execution/HelperOwnershipProof.swift')
coordinator = read('Sources/Environment/Helper/HelperDeploymentCoordinator.swift')
scanner = read('Sources/Environment/ReadOnlyPluginScanner.swift')
registry = read('Sources/Environment/PluginScanRegistry.swift')
identity = read('Sources/Core/Models/PluginIdentityVerificationResult.swift')
activation = read('Sources/Environment/Deployment/AppPluginActivationStateResolver.swift')
apps_view = read('Sources/Features/Apps/AppsView.swift')
plugin_scope = read('Sources/Features/Plugins/PluginListScope.swift')

check('request model contains no caller-supplied paths or payload bytes',
      all(token not in models for token in ['absolutePath', 'filePath', 'replacementBytes', 'dylibBytes']))
check('request uses safe leaf-name validation', 'HelperPolicy.isSafeLeafName(dylibFileName)' in models and 'HelperPolicy.isSafeLeafName(plistFileName)' in models)
check('IPC request and response message types registered', 'pluginIdentityAttestationRequest' in ipc and 'pluginIdentityAttestationResponse' in ipc)
check('dispatcher validates envelope/request identity and time', 'request.requestID == envelope.requestID' in dispatcher and 'request.validate(now: now' in dispatcher)
check('dispatcher routes through dedicated read-only attestor', 'attestor.attest(request, now: now)' in dispatcher)
check('dispatcher refuses identity attestation during pending recovery', 'recoveryStatus() == .clean' in dispatcher[dispatcher.find('case .pluginIdentityAttestationRequest'):dispatcher.find('case .pluginFilterMutationPrepareRequest')])
check('dispatcher requires an audit record before response', 'plugin_identity_attestation.' in dispatcher)
check('Helper runtime wires root plugin directory and dpkg databases', 'HelperPluginIdentityAttestor.Configuration' in read('Sources/Environment/Helper/Runtime/HelperRuntime.swift'))
check('attestor enforces effective UID root', 'geteuid() == 0' in attestor)
check('attestor independently resolves package ownership', 'HelperPackageOwnershipResolver().resolve' in attestor)
check('attestor verifies root-owned manifest and exact payloads', 'HelperOwnershipProofVerifier().verify' in attestor)
check('proof verifier checks manifest schema and plugin UUID', 'manifest.schemaVersion == 3' in verifier and 'UUID(uuidString: manifest.pluginID)' in verifier)
check('proof verifier checks dylib/plist hashes', 'dylibHash == manifest.dylibSHA256.lowercased()' in verifier and 'plistHash == manifest.plistSHA256.lowercased()' in verifier)
check('proof verifier checks Mach-O identity fingerprint', 'actualIdentity == expectedIdentity.lowercased()' in verifier)
check('Helper proof carries verified association/filter projection', 'softAssociations: associations' in verifier and 'filterConfiguration: PluginFilterConfiguration.parse(plistData)' in verifier)
check('attestation IPC projection is bounded', 'encoded.count <= 64 * 1024' in attestor)
check('attestor source contains no file mutation primitives', not any(token in attestor for token in ['O_WRONLY', 'renameat(', 'unlinkat(', 'fchmod(', 'write(']))
check('App coordinator binds response to original request ID', 'response.requestID == request.requestID' in coordinator and 'result.requestID == request.requestID' in coordinator)
check('scanner UUID is explicitly only an unverified lookup hint', 'only a lookup hint' in scanner and 'filterKitPluginID: filterKitPluginID' in scanner)
check('FilterKit-only scope requires verified ownership or Helper attestation', 'item.helperIdentityAttestation?.isVerified == true' in plugin_scope and 'item.filterKitPluginID != nil' not in plugin_scope)
check('registry attaches Helper attestation asynchronously', 'attachHelperIdentityAttestations' in registry and 'service.attest(enriched[index])' in registry)
check('activation identity resolver requires Helper attestation', 'guard let attestation = plugin.helperIdentityAttestation' in identity and 'attestation.isVerified' in identity)
check('activation identity resolver compares local file hashes and Mach-O identity', 'attestation.dylibSHA256?.caseInsensitiveCompare' in identity and 'attestation.machOIdentitySHA256?.caseInsensitiveCompare' in identity)
check('activation identity attestation expires after freshness window', 'attestation.isFresh(now: now, maximumAge: maximumAttestationAge)' in identity and 'maximumAge: TimeInterval = Self.maximumAge' in read('Sources/Core/Models/Helper/HelperPluginIdentityAttestationModels.swift'))
check('activation cross-check uses Helper-authoritative filter/association state', 'plugin.helperIdentityAttestation?.filterConfiguration' in activation and 'plugin.helperIdentityAttestation?.softAssociations' in activation)
check('App-side production mutation gate remains closed', 'static let productionMutationReleased = false' in read('Sources/Environment/Deployment/PluginToggleReleaseGate.swift'))
check('Coordinator and Helper association commit gates remain closed', 'static let pluginAssociationCommitReleased = false' in coordinator and 'static let pluginAssociationCommitReleased = false' in dispatcher)
check('activation preflight mutation release remains closed', 'static let mutationReleaseEnabled = false' in read('Sources/Environment/Deployment/PluginActivationPreflight.swift'))
check('APP detail switch remains preview-only and never calls mutation commit', 'previewStore.setPreview(newValue' in apps_view and 'commitPluginAssociation' not in apps_view)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'RESULT {len(checks)-len(failed)}/{len(checks)} passed')
if failed:
    sys.exit(1)
