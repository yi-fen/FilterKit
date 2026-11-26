# P2-24 Changelog

- Added immutable Batch ID / Batch digest / Transaction ID / Request ID / plugin / three-artifact hash binding.
- Dispatcher now generates and durably records a Transaction ID before entering the deployment pipeline.
- Ledger state transitions preserve the same Transaction ID.
- Pipeline derives the binding from validated batch metadata and Helper-authorized proof.
- Production backend passes the binding into the three-file transaction executor.
- Three-file transaction journal schema 2 persists the binding; schema 1 remains readable.
- Transaction receipts carry the Transaction ID and are checked against the dispatcher-created ID.
- Added read-only ledger/journal reconciliation verdicts and focused unit tests.
- Kept startup recovery inspection-only and all production write gates disabled.
