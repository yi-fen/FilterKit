# P2-06 — App Confirmation & Helper Commit IPC

- Added a dedicated `pluginFilterMutationCommitRequest` / `pluginFilterMutationCommitted` IPC message pair and a path-free commit receipt.
- Helper commit handling re-runs ownership verification and reads the current plist/manifest immediately before invoking the P2-05 two-file transaction. No prepared bytes or filesystem paths are accepted from the App.
- Wired the association transaction into the Helper runtime and Dispatcher.
- Added App-side `HelperDeploymentCoordinator.commitPluginAssociation(_:userConfirmed:)`, with explicit confirmation enforcement and strict receipt validation.
- Added a confirmation dialog to the plugin association preview. It explicitly reports that the commit remains locked and that no files were changed.
- Added tests for confirmation enforcement and the closed client release gate.

## Safety state

`HelperRequestDispatcher.pluginAssociationCommitReleased` and `HelperDeploymentCoordinator.pluginAssociationCommitReleased` remain `false`. The Helper rejects commit requests before authorization/transaction execution; the App coordinator also refuses to send them. Existing deployment gates remain unchanged and closed.

## Validation limits

No Xcode/iOS SDK build, XCTest run, RootHide device test, or real filesystem mutation was performed. This stage establishes the protocol and guarded code path only.
