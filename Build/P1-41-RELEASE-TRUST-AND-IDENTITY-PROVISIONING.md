# P1-41 — Release Trust & Helper Identity Provisioning

## Scope

P1-41 adds a versioned release trust record and a macOS release-pipeline helper that extracts identity from the **final signed** Helper executable. It binds the release ID, generation, bundle identifier, Helper version, CDHash and SHA-256. Publisher identity is an explicit policy, not inferred from a digest.

## Added components

- `HelperReleaseTrustManifest`: schema-versioned Codable record with strict release, generation, bundle, version, CDHash and SHA-256 validation.
- `HelperReleaseTrustVerifier`: binds the record to `HelperInstallerProvisioningBundle`, checks the observed executable SHA-256 and running CDHash, and optionally enforces Team ID plus leaf-certificate SHA-256.
- `HelperRuntimePreflight.inspect(releaseTrust:...)`: release-aware read-only preflight entry point. It runs trust verification before the existing journal inspection.
- `Build/Scripts/extract-helper-release-identity.sh`: macOS-only extraction from the final signed executable. It validates the signed Identifier, extracts CDHash and SHA-256, and can optionally pin Team ID and the extracted leaf certificate fingerprint.
- `HelperReleaseTrustTests`: XCTest coverage for manifest validation and identity mismatch rejection.

## Trust semantics and limitations

- `integrityOnly` establishes correspondence to locally provisioned digest pins; it does **not** establish publisher provenance.
- `pinnedAppleIdentity` requires a 10-character Team ID and leaf-certificate SHA-256. The verifier compares observations supplied by the platform integration; it does not itself establish a certificate chain, revocation status, notarization, or an independently trusted release-signing authority.
- The JSON trust manifest is not cryptographically signed in this phase. Its secure storage and provisioning authority remain part of the trusted installer boundary.
- CDHash and SHA-256 must be extracted after final signing. Any post-sign modification invalidates the release identity and requires regeneration.
- Runtime SHA-256 and publisher metadata acquisition are inputs to the new preflight API; the current project does not yet wire platform-specific acquisition into the running iOS/RootHide Helper process.
- No deployment, launchd bootstrap, or privilege gate is enabled.

## Release extraction

On macOS, after signing the Helper:

```sh
Build/Scripts/extract-helper-release-identity.sh \
  path/to/filterkit-helper release-1.4.1 41 cn.yfen.filterkit.helper 1.4.1 \
  Build/Release/HelperReleaseTrust.json
```

For an explicit publisher pin (requires a valid Team ID in the code signature):

```sh
Build/Scripts/extract-helper-release-identity.sh \
  path/to/filterkit-helper release-1.4.1 41 cn.yfen.filterkit.helper 1.4.1 \
  Build/Release/HelperReleaseTrust.json --pin-publisher
```

The script intentionally refuses non-macOS hosts and unsigned/invalid identity output.
