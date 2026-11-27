# P2-35 Validation Report

## Completed

- P2-35 soft-association static audit: 15/15.
- P2-35 compiled Host Smoke: passed (new association defaults inactive; existing activation bits preserved; remove/re-add restores the original bit; hard-bound App immutable; unauthorized plugin denied; soft removal leaves hard binding intact).
- P2-34 product architecture audit: 17/17.
- P2-33 plugin identity audit: 16/16.
- P2-32 App-detail plugin management audit: 13/13.
- P2-31 plugin management UI audit: 9/9 (updated to the P2-35 manager).
- P2-28 toggle release Host Smoke and audit: passed (10/10).
- P2-27 identity compatibility Host Smoke: passed.
- P2-25 authorized recovery Host Smoke: passed.
- P2-12 AF_UNIX Health Host Smoke: passed.
- P2-15 audit sink Host Smoke: passed.
- Swift syntax parse across App, Sources, HelperRuntime, Tests, and Build Swift files: passed.
- Focused Swift compilation of the association model and Host Smoke: passed.
- Python `py_compile` for Build scripts: passed.
- Shell `bash -n` for Build/Host scripts: passed.
- `Project.yml` YAML parse: passed.
- Chinese/English localization key parity and uniqueness: passed in P2-35 audit.

## Historical audit caveat

A broad sweep of older P2 static audits found legacy checks that no longer match the evolved implementation: P2-08, P2-16, P2-17, P2-19, P2-25, and P2-26 audit scripts report stale source-shape assertions. The P2-27 provisioning and P2-29 device-evidence scripts are command-line tools and return usage errors when invoked without their required signed-artifact/evidence arguments; they are not pass/fail static audits. P2-31 through P2-35 current product/UI audits pass. The older failures were not relabeled as passing.

## Not executed / not claimed

- XcodeGen generation or Xcode/iOS SDK build: unavailable in this Linux environment.
- SwiftUI type-check against the iOS SDK: not performed; Swift syntax parsing is not a substitute.
- iOS Simulator or physical iPhone UI verification: not performed.
- RootHide/ElleKit device association commit or live injection: not performed.
- Persistent association save: not implemented in P2-35. The manager edits only an in-memory draft and previews the diff.

## Safety

No Filter.plist, plugin dylib, or ownership Manifest was modified. The App page remains the only first-time dylib/plist import entry point. The Plugins page has no enable/disable controls. All production execution and association commit gates remain `false`.
