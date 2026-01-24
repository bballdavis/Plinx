#if canImport(XCTest)
import XCTest
@testable import PlinxCore

final class PlinxCoreTests: XCTestCase {
    func test_versionIsNonEmpty() {
        XCTAssertFalse(PlinxCore.version.isEmpty)
    }
}
#endif
