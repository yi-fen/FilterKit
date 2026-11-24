import XCTest
@testable import FilterKit

final class FilterPlistAssociationPreviewTests: XCTestCase {
    func testPreviewPreservesOriginalBundlesAndOnlyProposesAdditions() throws {
        let original: [String: Any] = [
            "Filter": [
                "Bundles": ["com.vendor.original"],
                "Executables": ["OriginalExecutable"],
                "VendorCustomKey": ["keep", "all"]
            ],
            "TopLevelVendorKey": "preserve"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        let preview = FilterPlistAssociationPreview.build(
            originalPlistData: data,
            effectiveBundleIdentifiers: ["com.example.source", "com.vendor.original"]
        )

        XCTAssertEqual(preview.originalBundles, ["com.vendor.original"])
        XCTAssertEqual(preview.proposedAdditions, ["com.example.source"])
        XCTAssertTrue(preview.proposedBundles.contains("com.vendor.original"))
        XCTAssertTrue(preview.removedBundles.isEmpty)
        XCTAssertTrue(preview.unknownKeys.contains("VendorCustomKey"))
        XCTAssertTrue(preview.preservesOriginalBytes)
        XCTAssertEqual(preview.originalPlistData, data)
        XCTAssertTrue(preview.requiresElleKitProfileVerification)
        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.originalPlistSHA256, SHA256Digest.hex(data))
    }

    func testInvalidOriginalPlistCannotBeApplied() {
        let preview = FilterPlistAssociationPreview.build(originalPlistData: Data("not a plist".utf8),
                                                          effectiveBundleIdentifiers: ["com.example.app"])
        XCTAssertEqual(preview.parseState, .invalid)
        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.reasonKey, "association.plist.invalid_original")
    }
}
