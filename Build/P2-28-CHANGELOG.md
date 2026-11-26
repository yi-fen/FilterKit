# P2-28 Changelog

- Added `PluginToggleReleaseGate` as a dedicated policy for staged per-App enable/disable and injection rollout.
- Added independent blockers for device-verified ElleKit strategy, App/Helper identity, clean recovery state, durable audit availability, FilterKit ownership, paired payload integrity, target App availability, hard-bound target protection, and explicit confirmation.
- Added unit tests for fail-closed behavior and each blocker group.
- Added a compiled host smoke runner and a 10-point static release-gate audit.
- Kept every existing production execution and association-commit release switch closed.
- Added rollout documentation describing the evidence required before any real write path can be enabled.
