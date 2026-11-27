#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
model = (root/'Sources/Core/Models/Helper/HelperAppPluginActivationProtocol.swift').read_text()
tests = (root/'Tests/UnitTests/HelperAppPluginActivationProtocolTests.swift').read_text()
dispatch = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
checks = {
 'single target Bundle ID in command': 'let targetBundleIdentifier: String' in model,
 'desired and expected state preconditions': 'let desiredEnabled: Bool' in model and 'let expectedEnabled: Bool' in model,
 'Filter hash bound': 'let expectedFilterSHA256: String' in model,
 'Manifest hash bound': 'let expectedManifestSHA256: String' in model,
 'snapshot revision required': 'snapshotRevision > 0' in model,
 'no filesystem path in command': 'let pluginPath:' not in model and 'let directoryPath:' not in model,
 'no replacement bytes in command': 'Data' not in model,
 'adapter maps only enable/disable': 'desiredEnabled ? .enableForApp : .disableForApp' in model,
 'plan binds request/plugin/target': 'requestID == command.requestID && pluginID == command.pluginID' in model and 'targetBundleIdentifier == command.targetBundleIdentifier' in model,
 'plan binds pre-state hashes': 'filterBeforeSHA256.caseInsensitiveCompare(command.expectedFilterSHA256)' in model and 'manifestBeforeSHA256.caseInsensitiveCompare(command.expectedManifestSHA256)' in model,
 'proof binds desired state': 'enabled == command.desiredEnabled' in model,
 'proof checks transaction semantics': 'command.expectedEnabled == command.desiredEnabled && transactionID == nil' in model,
 'tests cover protocol cases': tests.count('func test') >= 5,
 'production commit gate remains closed': 'static let pluginAssociationCommitReleased = false' in dispatch,
 'R4 protocol is dispatched through dedicated R5 routes': 'case .appPluginActivationPrepareRequest:' in dispatch and 'case .appPluginActivationCommitRequest:' in dispatch,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} passed')
raise SystemExit(0 if all(checks.values()) else 1)
