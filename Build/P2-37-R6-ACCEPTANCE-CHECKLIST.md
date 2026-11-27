# P2-37-R6 Acceptance Checklist

- [x] Commit payload binds exact Prepare command and plan.
- [x] Helper re-authorizes ownership and rereads both source files at Commit.
- [x] Actual target App state is independently derived from Manifest.
- [x] Fresh plan must exactly equal Prepare plan.
- [x] Existing dual-file Journal transaction is wired into the activation Commit branch.
- [x] Transaction Receipt is the only source of post-commit hashes and transaction ID.
- [x] Proof binds request, plugin, target App, desired state and both resulting hashes.
- [x] No-op proof has no transaction ID.
- [x] Production release gate remains closed.
- [ ] Xcode/iOS SDK build and Apple XCTest.
- [ ] Signed Darwin App/Helper IPC validation.
- [ ] RootHide/ElleKit device transaction and crash-recovery validation.
- [ ] Explicit release approval before enabling production writes.
