# P1-16 Test Report

- Source ZIP: `FilterKit-NEW-P1-15.zip`
- Source SHA-256: `e6082fb2eb509cb81c018eb35e8ec4a35db27ee6a1ee1ebc48fb5ba7c32f8820`
- Added portable backup codec, archive validation, and restore preview models.
- Added XCTest coverage for schema 2 round-trip, schema 1 compatibility, hash mismatch, traversal path rejection, and restore preview classification.

Environment constraints: this workspace has Swift on Linux but no Xcode/iOS SDK. Therefore Xcode build and XCTest execution are not claimed. Swift parser/typecheck and standalone smoke checks are reported separately in the delivery summary.
