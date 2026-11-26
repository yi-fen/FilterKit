# P2-08 — App-to-Helper End-to-End Integration

## Delivered

- The plugin association confirmation action now enters an async App-side commit handler.
- The handler builds an intent-only `HelperPluginFilterMutationRequest` from the current FilterKit plugin identity and freshly read plist/manifest bytes; only their SHA-256 digests cross IPC.
- The production service loads the signed `FilterKit-Helper-AppTrust.json` bundle resource, resolves the validated JBROOT, creates the pinned Darwin AF_UNIX transport, and calls the existing Helper commit coordinator.
- UI now distinguishes submitting, success receipt, invalid receipt, missing trust provisioning, and generic failure. A success message requires a receipt matching plugin ID and target bundle ID.
- Added protocol tests for explicit confirmation and the closed release gate.

## Deliberately fail-closed requirements

- `HelperDeploymentCoordinator.pluginAssociationCommitReleased` remains `false`.
- `HelperRequestDispatcher.pluginAssociationCommitReleased` remains `false`.
- The App transport factory refuses to start unless the signed `FilterKit-Helper-AppTrust.json` resource is provisioned with valid Helper CDHash pins and the main bundle ID matches.
- No automatic trust pin, socket path, CDHash, or root path is fabricated.
- No execution gate was opened and no device file was modified by this development stage.

## Verification boundary

Swift frontend parsing and Project.yml YAML parsing are performed for this package. XCTest, Xcode/iOS SDK build, signed resource embedding, live AF_UNIX peer identity verification, Helper handshake, RootHide device transaction, and ElleKit injection behavior require the macOS/Xcode signing environment and a RootHide test device. They are not claimed as passed here.

## Device release checklist

1. Provision `FilterKit-Helper-AppTrust.json` from the signed installer pipeline with the exact Helper CDHash.
2. Confirm `resolvedRootPath` points to the active RootHide JBROOT and the socket path matches the root-owned Helper manifest.
3. Build/sign both targets and verify kernel-reported Helper PID/CDHash and Helper-side App identity.
4. Exercise handshake and a deliberately rejected commit while both release gates remain closed.
5. Run crash-recovery and successful enable/disable tests on a disposable test plugin, verify both plist and manifest hashes, and confirm the dylib hash is unchanged.
6. Only after recorded device evidence and explicit release approval should the two association commit gates be considered for release.
