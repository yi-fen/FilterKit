#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
dispatch = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
handshake = (root/'Sources/Core/Models/Helper/HelperHandshake.swift').read_text()
models = (root/'Sources/Core/Models/Helper/HelperIPCModels.swift').read_text()
tests = (root/'Tests/UnitTests/HelperRequestDispatcherTests.swift').read_text()
checks = {
    'dedicated prepare and commit message types': all(x in models for x in ['appPluginActivationPrepareRequest', 'appPluginActivationCommitRequest', 'appPluginActivationPrepared', 'appPluginActivationCommitted']),
    'prepare and commit requests in transport allowlist': '.appPluginActivationPrepareRequest' in handshake and '.appPluginActivationCommitRequest' in handshake,
    'response types excluded from request allowlist': '.appPluginActivationPrepared' not in handshake and '.appPluginActivationCommitted' not in handshake,
    'dispatcher has prepare route': 'case .appPluginActivationPrepareRequest:' in dispatch,
    'dispatcher has commit route': 'case .appPluginActivationCommitRequest:' in dispatch,
    'request ID bound to envelope': 'command.requestID == envelope.requestID' in dispatch and 'commit.requestID == envelope.requestID' in dispatch,
    'envelope and command timestamps bound': 'command.createdAt.timeIntervalSince(envelope.createdAt)' in dispatch and 'commit.createdAt.timeIntervalSince(envelope.createdAt)' in dispatch,
    'command freshness and shape validated': 'command.validate(now: now, clockSkewLimit: clockSkewLimit)' in dispatch and 'commit.validates(now: now, clockSkewLimit: clockSkewLimit)' in dispatch,
    'recovery gate checked on both routes': dispatch.count('recoveryStatus() == .clean') >= 2,
    'prepare delegates to Helper authorizer': 'authorizer.prepare(command.makeMutationRequest(), now: now)' in dispatch,
    'plan echoes exact command target': 'plan.validates(command: command)' in dispatch,
    'actual previous activation state read from Helper manifest': 'actualPreviousEnabled' in dispatch and 'currentAssociations.first(where:' in dispatch,
    'expected previous state independently checked': dispatch.count('actualEnabled == command.expectedEnabled') + dispatch.count('actualPreviousEnabled == command.expectedEnabled') >= 2,
    'commit reauthorizes from freshly read files': '_ = try authorizer.prepare(command.makeMutationRequest(), now: now)' not in dispatch and 'let prepared = try authorizer.prepare(command.makeMutationRequest(), now: now)' in dispatch,
    'production commit remains fail-closed': 'guard activationCommitExecutionEnabled else' in dispatch and 'activationCommitExecutionEnabled: Bool = false' in dispatch,
    'commit route executes only after fresh plan binding': 'case .appPluginActivationCommitRequest:' in dispatch and 'freshPlan == commit.preparedPlan' in dispatch and dispatch.index('guard activationCommitExecutionEnabled else') < dispatch.index('transaction.execute(prepared)'),
    'production association gate remains false': 'static let pluginAssociationCommitReleased = false' in dispatch,
    'replay guard remains before dispatch': 'replayGuard.accept(envelope.requestID, now: now)' in dispatch,
    'audit required for prepared response': 'app_plugin_activation_prepared_read_only' in dispatch,
    'tests cover allowlist and malformed/replay': 'testAppPluginActivationRoutesAreExplicitlyAllowlisted' in tests and 'testAppPluginActivationPrepareRejectsMalformedPayloadAndReplay' in tests,
    'no APP activation commit call from feature layer': not any('appPluginActivationCommitRequest' in p.read_text(errors='ignore') for p in (root/'Sources/Features').rglob('*.swift')) if (root/'Sources/Features').exists() else True,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} passed')
raise SystemExit(0 if all(checks.values()) else 1)
