import StoreKitTest
import XCTest

/// The App Review screenshots of the purchase screens, captured by fastlane
/// (`bundle exec fastlane iap_screenshots`) and uploaded with the in-app
/// purchases by `upload_iap`. The products and prices come from
/// Config/Tinytide.storekit through a StoreKit test session, so no App Store
/// account is involved.
final class InAppPurchaseScreenshots: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Tinytide", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        // Never a supporter yet, so the subscription page shows both plans.
        session.clearTransactions()
    }

    override func tearDown() {
        session = nil
    }

    @MainActor
    func testTipJar() {
        capture(screen: "tipjar", name: "tip_jar", price: "$0.99")
    }

    @MainActor
    func testSupporter() {
        capture(screen: "supporter", name: "supporter", price: "$9.99")
    }

    @MainActor
    private func capture(screen: String, name: String, price: String) {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-demoMode", "-demoScreen", screen]
        app.launch()
        // A screenshot without prices would be no use to App Review.
        let priced = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", price)).firstMatch
        XCTAssertTrue(
            priced.waitForExistence(timeout: 30),
            "No \(price) on the \(screen) screen: StoreKit didn't load the products from Tinytide.storekit"
        )
        snapshot(name, timeWaitingForIdle: 2)
        app.terminate()
    }
}
