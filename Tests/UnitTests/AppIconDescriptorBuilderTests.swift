import XCTest
@testable import FilterKit

final class AppIconDescriptorBuilderTests: XCTestCase {
    func testReadsNestedPrimaryIconNameAndGeneratesR16CompatibleFileCandidates() {
        let bundle = URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true)
        let descriptor = ContainerDirectoryAppScannerIconBuilder.make(plist: [
            "CFBundleIcons": ["CFBundlePrimaryIcon": [
                "CFBundleIconName": "PrimaryAsset",
                "CFBundleIconFiles": ["AppIcon60x60"]
            ]]
        ], bundleURL: bundle)

        XCTAssertEqual(descriptor?.assetName, "PrimaryAsset")
        let names = Set(descriptor?.fileCandidates.map(\.lastPathComponent) ?? [])
        XCTAssertTrue(names.contains("AppIcon60x60"))
        XCTAssertTrue(names.contains("AppIcon60x60.png"))
        XCTAssertTrue(names.contains("AppIcon60x60@2x.png"))
        XCTAssertTrue(names.contains("AppIcon60x60@3x.png"))
    }

    func testReadsLegacyTopLevelIconFile() {
        let bundle = URL(fileURLWithPath: "/Applications/Legacy.app", isDirectory: true)
        let descriptor = ContainerDirectoryAppScannerIconBuilder.make(plist: [
            "CFBundleIconFile": "LegacyIcon"
        ], bundleURL: bundle)
        XCTAssertTrue(descriptor?.fileCandidates.contains(where: { $0.lastPathComponent == "LegacyIcon@2x.png" }) == true)
    }
}
