import XCTest
import AppKit
@testable import TGUIKit

final class InterfaceFontProviderTests: XCTestCase {
    override func tearDown() {
        InterfaceFontProvider.install(nil)
        super.tearDown()
    }

    func testNativeFontCacheDoesNotRetainAnInstalledOverride() {
        InterfaceFontProvider.install { _, _, _ in .systemFont(ofSize: 41) }
        FontCacheKey.initializeCache()
        XCTAssertEqual(NSFont.normal(13).pointSize, 41)
        InterfaceFontProvider.install(nil)
        XCTAssertEqual(NSFont.normal(13).pointSize, 13)
    }

    func testNestedNativeScopeRestoresOverrideAfterThrowing() {
        enum Failure: Error { case expected }
        InterfaceFontProvider.install { _, _, _ in .systemFont(ofSize: 41) }
        XCTAssertThrowsError(try InterfaceFontProvider.withNativeFonts {
            XCTAssertEqual(NSFont.normal(13).pointSize, 13)
            InterfaceFontProvider.withNativeFonts { XCTAssertEqual(NSFont.normal(14).pointSize, 14) }
            XCTAssertEqual(NSFont.normal(13).pointSize, 13)
            throw Failure.expected
        })
        XCTAssertEqual(NSFont.normal(13).pointSize, 41)
    }

    func testProviderCanReenterInstallationWithoutHoldingTheProviderLock() {
        InterfaceFontProvider.install { _, _, _ in
            InterfaceFontProvider.install(nil)
            return .systemFont(ofSize: 41)
        }
        XCTAssertEqual(NSFont.normal(13).pointSize, 41)
        XCTAssertEqual(NSFont.normal(13).pointSize, 13)
    }
}
