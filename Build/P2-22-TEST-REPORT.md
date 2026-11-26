# P2-22 Host Validation Report

Date: 2026-11-26

| Check | Result |
|---|---|
| P2-16 compatibility static audit | 11/11 PASS |
| P2-17 static audit | 11/11 PASS |
| P2-18 static audit | 10/10 PASS |
| P2-19 static audit | 12/12 PASS |
| P2-20 static audit | 12/12 PASS |
| P2-21 static audit | 14/14 PASS |
| P2-22 static audit | 11/11 PASS |
| Swift source syntax parse (Sources, HelperRuntime, Tests) | PASS |
| Idempotency ledger focused Linux typecheck | PASS |
| AF_UNIX Health smoke | PASS |
| Audit sink smoke | PASS |
| Project.yml YAML parse | PASS |

Not run: full XCTest, Xcode/iOS SDK build, Darwin-specific typecheck, RootHide device testing, process-kill/restart recovery testing. The idempotency ledger is process-local and is not durable across Helper restart. A retry after restart must be resolved against the root-owned transaction journal and filesystem observations; that end-to-end path remains unreleased and unverified. No production write gate was enabled.
