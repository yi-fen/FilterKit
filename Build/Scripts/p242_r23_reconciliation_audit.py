from pathlib import Path

root = Path(__file__).resolve().parents[2]
dispatcher = (root / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift").read_text()
policy = (root / "Sources/Core/Models/Helper/HelperHandshake.swift").read_text()
store = (root / "Sources/Environment/Deployment/AppPluginActivationOperationStore.swift").read_text()
view = (root / "Sources/Features/Apps/AppsView.swift").read_text()
transaction = (root / "Sources/Environment/Helper/Execution/HelperPluginFilterConfigurationTransaction.swift").read_text()

query_start = dispatcher.index("case .appPluginActivationTransactionQueryRequest:")
reconcile_start = dispatcher.index("case .appPluginActivationTransactionReconcileRequest:", query_start)
prepare_start = dispatcher.index("case .appPluginActivationPrepareRequest:", reconcile_start)
query_block = dispatcher[query_start:reconcile_start]
reconcile_block = dispatcher[reconcile_start:prepare_start]

assert "resolveUnknown" not in query_block
assert "finalizeResolvedActivationJournal" not in query_block
assert "request.validate(now: now" in reconcile_block
assert "ledger.resolveUnknown" in reconcile_block
assert reconcile_block.index("ledger.resolveUnknown") < reconcile_block.index("finalizeResolvedActivationJournal")
assert ".appPluginActivationTransactionReconcileRequest" in policy
assert "func reconcileWithHelper(userConfirmed: Bool) async" in store
assert "activation_verify_helper" in view
assert "finalizeResolvedActivationJournal" in transaction
assert "static let appPluginActivationCommitReleased = false" in (root / "Sources/Environment/Helper/HelperDeploymentCoordinator.swift").read_text()
print("R23 source audit: 10 assertions passed")
