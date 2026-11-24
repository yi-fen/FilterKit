# P1-28 — Helper Deployment Pipeline Integration

## Scope

P1-28 adds a single orchestration boundary for a complete dylib + Filter.plist batch. It connects batch validation, root-side route evidence, route-specific authorization, closed execution-plan validation, paired executor invocation, and a batch-level receipt.

## Added

- `HelperDeploymentPipeline.swift`
  - `HelperDeploymentPipelineBackend` is the root-side adapter contract.
  - `HelperDeploymentPipeline` validates the batch, resolves first-install vs update, invokes exactly one authorization path, validates the returned ownership proof and both closed plans, then invokes one paired transaction executor.
  - The proof's first-install authorization bit must match the selected route.
  - The returned transaction receipt must bind the submitted plugin UUID, both operation IDs, exact changed paths, and both hashes.
  - `HelperDeploymentBatchReceipt` is the batch-level success response model.
- IPC message type `deploymentBatchReceipt`.
- `HelperRequestDispatcher` accepts an optional pipeline and maps authorization, malformed-plan, and execution failures to stable rejection codes. The pipeline is called only after both independent execution gates pass.
- `HelperRuntime` explicitly constructs the dispatcher without a production pipeline backend. Runtime remains health-only and fail-closed.
- `Build/Scripts/p1-28-pipeline-smoke.swift` exercises the orchestration through a fake backend.

## Security boundaries / not yet production-complete

- No concrete production `HelperDeploymentPipelineBackend` is registered. The protocol deliberately requires a platform adapter to derive route evidence itself, perform first-install bootstrap or existing-manifest verification, package ownership checks, Mach-O/plist verification, build plans from root-verified staging bytes, and invoke `HelperSafeFileExecutor`.
- The smoke backend is test-only and is not included in HelperRuntime.
- `HelperRequestDispatcher.executionReleased`, `HelperDeploymentCoordinator.executionReleased`, and `HelperDeploymentManifest.executionEnabled` remain false.
- Runtime passes `deploymentPipeline: nil`; it continues to reject deployment requests. No real TweakInject writes were performed.
- A transaction receipt mismatch after executor return is treated as a deployment failure; the durable transaction journal remains the reconciliation mechanism. This path requires further fault-injection tests before production use.
- No automatic recovery mutation was enabled.

## Verification

- Full Swift source syntax parse: PASS.
- Helper pipeline / dispatcher dependency subset Linux typecheck: PASS.
- P1-28 isolated orchestration smoke: PASS — first-install route, update route, unknown ownership rejection, authorization failure, and inconsistent receipt rejection.
- P1-27 batch protocol regression smoke: PASS.
- Project configuration verification: PASS.
- Architecture verification: PASS.
- Localization parity: PASS — 225 keys in zh-Hans and en.
- Local build static checks: PASS.
- ZIP integrity: checked after packaging.

## Not performed

No XcodeGen, Xcode/iOS SDK build, XCTest execution, Darwin compile, launchd installation, RootHide/Rootless device validation, or real TweakInject filesystem mutation was performed in this environment.
