import UIKit
import XCTest
@testable import Tinytide

final class TipJarTests: XCTestCase {
    /// Product IDs must match App Store Connect and Config/Tinytide.storekit.
    func testProductIDsMatchStoreKitConfiguration() throws {
        XCTAssertEqual(TipJar.Tier.allCases.map(\.productID), ["tinytide.tip.small", "tinytide.tip.medium", "tinytide.tip.large"])
        for tier in TipJar.Tier.allCases {
            XCTAssertFalse(tier.fallbackTitle.isEmpty)
            XCTAssertFalse(tier.blurb.isEmpty)
            XCTAssertFalse(tier.emoji.isEmpty)
        }
    }
}

final class SupporterTests: XCTestCase {
    /// Product IDs must match App Store Connect and Config/Tinytide.storekit.
    func testSubscriptionProductIDs() {
        XCTAssertEqual(Supporter.productIDs, ["tinytide.supporter.monthly", "tinytide.supporter.yearly"])
    }

    func testOnlyDefaultsAreFree() {
        XCTAssertEqual(AppTheme.allCases.filter(\.isFree), [.lullaby])
        XCTAssertEqual(AlternateIcon.allCases.filter(\.isFree), [.standard])
        XCTAssertNil(AlternateIcon.standard.iconName)
    }

    func testAlternateIconsExistInAssetCatalog() {
        for icon in AlternateIcon.allCases {
            XCTAssertNotNil(UIImage(named: icon.previewImage), "Missing preview image for \(icon)")
        }
        let declared = (Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])?["CFBundleAlternateIcons"] as? [String: Any]
        for name in AlternateIcon.allCases.compactMap(\.iconName) {
            XCTAssertNotNil(declared?[name], "Alternate icon \(name) is not in the built Info.plist")
        }
    }
}
