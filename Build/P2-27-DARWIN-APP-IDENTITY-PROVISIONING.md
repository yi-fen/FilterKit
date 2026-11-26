# P2-27 — Darwin App Identity Provisioning & Maintenance Channel Validation

## Scope

P2-27 strengthens the signed App-to-root-Helper trust hand-off without enabling deployment or recovery writes.

### Changes

- App-bundled `HelperAppTrustConfiguration` can now carry explicit allowed Helper UID/GID expectations. Newly generated provisioning pins both to root (`0`); older schema-1 JSON without these optional fields remains decodable and uses the same root-only defaults.
- `HelperProductionTransportFactory` checks that the running App's own kernel-reported CDHash is readable and well-formed before opening the socket. The App's exact CDHash is deliberately not embedded into its own signed bundle: that would create a self-referential signing problem. The trusted installer writes the final App CDHash into the root-owned Helper manifest, and the Helper checks the connecting App against that pin.
- The App-side peer trust evaluator now consumes the Helper UID/GID policy from the embedded configuration rather than hard-coding an unstructured policy at the call site.
- `HelperMaintenanceChannelCompatibilityPolicy` cross-checks installer provisioning, embedded App trust generation/bundle/Helper CDHash, observed final App and Helper CDHashes, measured App UID/GID, and root Helper UID/GID.
- `p209_provision_helper_trust.py` emits explicit root Helper UID/GID pins in both prepare and finalize outputs.
- `p227_identity_provisioning_audit.py` is a read-only macOS audit for final signed App/Helper products. It verifies signatures with `codesign --verify --strict --deep`, checks signed identifiers and CDHashes, verifies embedded App trust contents, and compares target-measured App UID/GID against installer provisioning.

## Host-side policy smoke

Run `Build/Host/run-p227-identity-compatibility-smoke.sh` on a Swift host to compile and execute positive/mismatch/legacy-decoding policy cases and the static gate audit. This does not exercise Darwin kernel APIs.

## macOS audit usage

Run only after both binaries have their final signatures and the App bundle contains `FilterKit-Helper-AppTrust.json`:

```sh
python3 Build/scripts/p227_identity_provisioning_audit.py \
  --app build/FilterKit.app \
  --helper build/FilterKitHelper \
  --provisioning build/p209-provisioning/FilterKit-Helper-InstallerProvisioning.json \
  --client-uid 501 --client-gid 501 \
  --helper-identifier cn.yfen.filterkit.helper
```

Replace UID/GID with values measured on the target RootHide device. They are not inferred from the macOS build host. Optionally pass `--expected-team-id` when a Team ID is part of the release policy.

## Trust semantics and limits

- The App's own CDHash is checked for availability/format in the App process; the exact trusted App CDHash is enforced by the root Helper against its root-owned manifest. It is intentionally not self-pinned inside the signed App bundle.
- The embedded App trust file is configuration, not a signature. Its integrity relies on the final App code signature and trusted signing/provisioning pipeline.
- `codesign --verify` verifies the local code signature under the host's trust evaluation; this script does not independently establish notarization, revocation freshness, or a separate release authority.
- UID/GID values supplied to the audit must come from the target device. A host-side pass cannot establish device UID/GID or AF_UNIX permission behavior.
- No socket connection, installation, launchd action, file mutation, or RootHide runtime test is performed by the audit.

## Validation boundary

Host-side policy tests and static audits can validate mismatch handling. The macOS final-signature audit requires macOS/Xcode signing tools and actual signed artifacts. RootHide device validation remains pending. All production execution and plugin-association commit gates remain `false`.
