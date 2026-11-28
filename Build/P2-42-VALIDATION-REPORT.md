# P2-42 Validation Report

Date: 2026-11-27

## Validation performed

- `swiftc -parse` across all Swift files under `Sources` and `Tests`.
- Standalone Swift typecheck of `PluginModels.swift` and `PluginLifecyclePolicy.swift`.
- Standalone Swift typecheck of `HelperPackageOwnershipResolver.swift` with minimal host shims for its existing `HelperPolicy` and `SHA256Digest` dependencies.
- Executed a compiled lifecycle smoke harness: APP-only enable, uninstall denial while any App activation is enabled, Fixed Owner immutability, and App-uninstall availability derivation all passed.
- Executed a compiled Helper SHA-256 smoke against a temporary root-owned dpkg `.list` and plugin directory: exact package-managed bytes were detected; a different SHA-256 was not detected.
- Static inspection confirms the Helper deployment backend catches `HelperPackageOwnershipProof.ProofError.packageOwned` distinctly at the final execution-time ownership check and invokes the dpkg-owned dylib SHA-256 scan at authorization and immediately before transaction execution.
- Static inspection confirms first-install manifest, dylib, and plist destination absence are rechecked before transaction execution; `HelperThreeFileTransactionExecutor` independently enforces all three leaves absent while holding its process lock.
- `Project.yml` YAML parse.
- ZIP integrity check after packaging.

## Not run / limitations

- Linux environment has no Xcode/iOS SDK; no iOS app build or XCTest execution through Xcode.
- The new XCTest source was syntax-parsed, not executed by XCTest; the equivalent core lifecycle scenarios were exercised by the standalone smoke harness.
- No RootHide/ElleKit device validation.
- Production injection, enable/disable commit, uninstall, and restore write gates remain closed.
- This increment establishes policy and strengthens existing deployment preflight; it does not implement privileged uninstall execution or claim actual plugin injection success.

## P2-42-R2 validation addendum

- `swiftc -parse` across all Swift files under `Sources` and `Tests` — passed.
- `p231_plugin_management_ui_audit.py` — 9/9 passed.
- `p232_app_detail_plugin_management_audit.py` — 13/13 passed.
- `p234_product_architecture_audit.py` — 17/17 passed.
- `p235_soft_association_audit.py` — 15/15 passed.
- Chinese and English localization: 485 keys each, no duplicate keys, key sets identical.
- Verified the Plugin detail uninstall button is disabled and the Helper/production gates remain closed.
- No Xcode/iOS build, XCTest run, or RootHide/ElleKit device acceptance was performed in this Linux environment.
