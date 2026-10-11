import XCTest
@testable import Lullo

final class TipJarTests: XCTestCase {
    /// Product IDs must match App Store Connect and Config/Lullo.storekit.
    func testProductIDsMatchStoreKitConfiguration() throws {
        XCTAssertEqual(TipJar.Tier.allCases.map(\.productID), ["lullo.tip.small", "lullo.tip.medium", "lullo.tip.large"])
        for tier in TipJar.Tier.allCases {
            XCTAssertFalse(tier.fallbackTitle.isEmpty)
            XCTAssertFalse(tier.blurb.isEmpty)
            XCTAssertFalse(tier.emoji.isEmpty)
        }
    }
}
