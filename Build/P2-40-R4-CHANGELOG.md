# P2-40-R4 — persisted first-successful-batch binding policy

## Implemented

- Added `PluginImportBatchPolicy.swift`.
- The first successfully committed import batch is assigned `fixedOwner` using the APP detail page from which the batch was imported.
- Every subsequent batch is assigned `additionalAssociation` to the importing App.
- All plugins in one ZIP/DEB batch share one binding decision.
- All successful imports default to enabled (`defaultsEnabled = true`).
- The policy state is atomically persisted only after a non-empty successful batch is acknowledged.
- Failed, empty, cancelled, or abandoned batches do not consume first-batch status.
- Concurrent in-process import batches are serialized by an actor reservation.
- Added unit tests for first batch, failed/cancelled batch, later association, default-enabled behavior, and restart persistence.

## Product terminology

- `fixedOwner` → **固定归属** / **Fixed Owner**.
- `additionalAssociation` → **扩展关联** / **Additional App Association**.

## Integration boundary

This is the durable policy layer, not a claim of end-to-end installation. The App import preview and Helper commit path are not yet wired to this store. In addition, the current Helper bootstrap, association-plan, and backup/restore code still require a non-optional fixed-owner Bundle ID. A coordinated follow-up must make soft-only plugins (`hardBoundBundleIdentifier = nil`) valid across manifest verification, ownership proofs, association editing, backup/restore, and Helper transactions before later batches can be deployed under the new policy.

## Not changed

- ZIP and DEB archive parsing.
- Plugin backup generation during import.
- Helper production execution and signed IPC.
- Existing hard-bound immutability rules.
- Production release gates (remain closed).
