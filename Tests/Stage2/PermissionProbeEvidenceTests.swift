//
//  PermissionProbeEvidenceTests.swift
//  FilterKit Stage 2 — PermissionProbe D1（证据模型往返与可选字段）
//
//  覆盖规格 §5：全字段往返；可选 nil 省略键；JSON null 解码落 nil；
//  错误域/码保留；分类缺失解码为 nil。
//

import Foundation
import XCTest
@testable import Models

final class PermissionProbeEvidenceTests: XCTestCase {

    private func makeEvidence(status: ProbeStatus = .passed) -> ProbeEvidence {
        ProbeEvidence(
            id: "evidence-001",
            probeID: "DIRECTORY-ACCESS",
            operation: .stat,
            category: .jbroot,
            status: status,
            target: "/private/var/jb/usr/lib/TweakInject",
            observedValue: "Entries: 12",
            errorDomain: "NSPOSIXErrorDomain",
            errorCode: 13,
            executedAt: "2026-11-20T00:00:00Z"
        )
    }

    func testFullFieldsRoundTrip() throws {
        let evidence = makeEvidence()
        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(ProbeEvidence.self, from: data)
        XCTAssertEqual(decoded, evidence)
        XCTAssertEqual(decoded.id, "evidence-001")
        XCTAssertEqual(decoded.probeID, "DIRECTORY-ACCESS")
        XCTAssertEqual(decoded.operation, .stat)
        XCTAssertEqual(decoded.category, .jbroot)
        XCTAssertEqual(decoded.errorCode, 13)
    }

    func testNilOptionalsOmitKeysOnEncode() throws {
        let evidence = ProbeEvidence(probeID: "DYLIB-METADATA", status: .unknown)
        let data = try JSONEncoder().encode(evidence)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys: Set<String> = object.map { Set($0.keys) } ?? []
        XCTAssertFalse(keys.contains("category"))
        XCTAssertFalse(keys.contains("target"))
        XCTAssertFalse(keys.contains("observedValue"))
        XCTAssertFalse(keys.contains("errorDomain"))
        XCTAssertFalse(keys.contains("errorCode"))
        XCTAssertFalse(keys.contains("executedAt"))
    }

    func testNullOptionalsDecodeToNil() throws {
        let json = """
        {
          "id": "evidence-null",
          "probeID": "DYLIB-METADATA",
          "category": null,
          "status": "unknown",
          "target": null,
          "observedValue": null,
          "errorDomain": null,
          "errorCode": null,
          "executedAt": null
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ProbeEvidence.self, from: data)
        XCTAssertEqual(decoded.probeID, "DYLIB-METADATA")
        XCTAssertEqual(decoded.status, .unknown)
        XCTAssertNil(decoded.category)
        XCTAssertNil(decoded.target)
        XCTAssertNil(decoded.observedValue)
        XCTAssertNil(decoded.errorDomain)
        XCTAssertNil(decoded.errorCode)
        XCTAssertNil(decoded.executedAt)
    }

    func testMissingCategoryDecodesToNil() throws {
        let json = """
        { "id": "evidence-missing-category", "probeID": "PLIST-READ", "status": "not_executed" }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ProbeEvidence.self, from: data)
        XCTAssertNil(decoded.category)
        XCTAssertEqual(decoded.status, .notExecuted)
    }

    func testErrorFieldsPreservedOnRoundTrip() throws {
        let evidence = ProbeEvidence(
            probeID: "TWEAKINJECT-ACCESS",
            category: .ellekit,
            status: .permissionDenied,
            target: "/private/var/jb/usr/lib/TweakInject",
            errorDomain: "NSCocoaErrorDomain",
            errorCode: 257
        )
        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(ProbeEvidence.self, from: data)
        XCTAssertEqual(decoded.errorDomain, "NSCocoaErrorDomain")
        XCTAssertEqual(decoded.errorCode, 257)
    }
}
