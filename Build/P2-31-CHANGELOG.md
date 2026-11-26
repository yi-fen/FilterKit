# P2-31 Changelog

- Removed the non-compilable PID-generation read from the Darwin peer identity provider: `proc_pidinfo`, `proc_bsdinfo`, `PROC_PIDTBSDINFO`, and the non-existent `pbi_pidversion` field are not exported by the public iOS SDK; the generation counter lives only in XNU PRIVATE headers (`proc_uniqidentifierinfo`, flavors 17/18).
- Kept `pidVersion` and the generation policy/diagnostic markers as reserved optional evidence; the provider records `pidVersion: nil` on the public SDK and never fabricates a value.
- Changed the peer acceptance hard gate from "complete audit token + PID generation" to "complete LOCAL_PEERTOKEN audit token digest + live PID" via the new `hasKernelPeerEvidence` policy, applied to both transport paths and the recovery authorization check.
- Fixed the `HelperRequestDispatcher` call-site argument order to match the initializer declaration (`deploymentIdempotencyLedger` before `deploymentPipeline`).
- Changed two never-mutated Keychain `query` locals from `var` to `let`; added a pure-policy test for the new kernel peer evidence gate.
- Credentials double-read, audit-token double-read, identity/credential match, and CDHash pin trust checks are unchanged; no production write gate, Rootless DEB layout, injection, or target-app modification was added.
