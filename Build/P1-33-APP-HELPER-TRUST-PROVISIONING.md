# P1-33 — App/Helper Trust Provisioning & Maintenance Authorization Boundary

## Scope

P1-33 formalizes the two-sided CDHash trust configuration and adds an App-side Darwin transport factory. It does not install the Helper, create production pins automatically, enable maintenance mutation, or release deployment.

## Trust model

The trust relationship is deliberately asymmetric at each endpoint and mutual across the connection:

- App -> Helper: the App obtains the connected peer PID from the AF_UNIX socket and asks the Darwin identity provider for the kernel-reported CDHash. The App accepts only UID 0 and a Helper CDHash pinned in its App-bundled `HelperAppTrustConfiguration`.
- Helper -> App: the Helper obtains peer credentials from the accepted socket and validates UID plus kernel-reported App CDHash against the root-owned `HelperDeploymentManifest`.
- Both sides retain the per-connection Hello nonce. The operation envelope must carry the nonce from that connection.

A socket connection, path, bundle identifier, or caller-supplied hash is not itself proof of identity. The CDHash comes from the kernel `csops(CS_OPS_CDHASH)` integration point.

## Provisioning sequence

The App's own CDHash cannot be embedded into its own signed bundle without creating a self-reference. Provisioning therefore uses two artifacts:

1. Build and sign `FilterKitHelper`; obtain its final CDHash.
2. Generate `HelperAppTrustConfiguration` containing the exact Helper CDHash and `cn.yfen.filterkit`; embed it in the App before final App signing.
3. Sign the App and obtain its final CDHash.
4. The trusted installer creates the root-owned Helper manifest with both exact App and Helper CDHashes, the allowed non-root App UID, and `executionEnabled=false`.
5. The App loads the embedded App trust configuration and creates its coordinator with `HelperProductionTransportFactory`.

`HelperTrustPinSet` is a validation/provisioning value, not a signature. It must be populated by the trusted build/installer pipeline, never from IPC or ordinary App UI input. This phase does not implement an installer that signs or writes the root manifest.

## Implemented

- `HelperTrustPinSet`: validates bundle ID, non-root client UIDs, exact 40-hex CDHashes, duplicate pins, bounded pin rotation set, and generation.
- `makeDisabledManifest`: creates a Helper manifest using the exact provisioned pins while keeping execution disabled.
- `makeAppConfiguration`: creates the App-bundled Helper pin artifact without embedding the App's own CDHash.
- `HelperAppTrustConfiguration`: validates the App bundle identity and pinned Helper CDHashes.
- `HelperProductionTransportFactory`: on Darwin, checks the App bundle identifier, configures kernel peer identity lookup, and accepts only a root Helper with a pinned CDHash.
- `HelperTrustConfigurationValidator`: Helper startup refuses missing App/Helper pins, malformed hashes, duplicate/empty UID sets, and root App UIDs.
- `HelperSecureManifestStore`: now rejects empty CDHash pin sets and root/duplicate client UIDs before Runtime startup.

## Maintenance authorization boundary

Maintenance `inspect` remains read-only. `reconcileThreeFileTransaction` continues to return `recoveryNotReleased`. No user confirmation can override the Helper's release gate. A future recovery release must be a separately provisioned policy and audited Helper-side authorization, not a client Boolean.

## Security invariants

- App verifies Helper CDHash and root UID before trusting a response.
- Helper verifies App CDHash and allowed non-root UID before dispatch.
- Kernel credentials/CDHash are used; no payload field supplies identity.
- Fresh session nonce remains bound to the authenticated socket connection.
- Helper manifest remains root-owned 0600 and trust pins must be non-empty.
- Deployment gates remain false; maintenance recovery mutation remains closed.
- No launchd installation, real TweakInject writes, target App modification, or re-signing is performed.

## Not implemented / not validated

- Trusted installer implementation that obtains final CDHashes and writes the root manifest.
- Actual bundled trust JSON resource and update/rotation delivery.
- App composition-root injection of the production coordinator; Settings remains `Not configured` until a verified coordinator is supplied.
- Darwin `csops`, `LOCAL_PEERPID`, `getpeereid`, and AF_UNIX behavior on target iOS versions.
- Xcode/iOS SDK build, code-signing validation, launchd installation, RootHide/Rootless device test, and device recovery tests.
