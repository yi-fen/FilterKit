import XCTest
@testable import FilterKit

final class PluginSourceOperationPolicyTests: XCTestCase {
    func testFilterKitOwnershipAllowsManagedOperations() {
        for operation in [PluginManagedOperation.inject, .export, .uninstall, .restore] {
            XCTAssertEqual(PluginSourceOperationPolicy.decision(for: .filterKit, operation: operation), .allow)
        }
    }

    func testPackageManagerExactRestoreAndInjectionDuplicatesAreSkipped() {
        for operation in [PluginManagedOperation.restore, .inject] {
            XCTAssertEqual(PluginSourceOperationPolicy.decision(for: .packageManager,
                operation: operation, exactPackageManagedSHA256Match: true), .skipExternalDuplicate)
        }
    }

    func testPackageManagerIsNeverAdoptedOrModified() {
        for operation in [PluginManagedOperation.inject, .export, .uninstall, .restore] {
            XCTAssertEqual(PluginSourceOperationPolicy.decision(for: .packageManager,
                operation: operation), .denyReadOnlySource)
        }
    }

    func testUnknownOriginRemainsReadOnlyEvenWhenHashMatches() {
        XCTAssertEqual(PluginSourceOperationPolicy.decision(for: .unknown,
            operation: .restore, exactPackageManagedSHA256Match: true), .denyReadOnlySource)
    }
}
