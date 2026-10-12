import XCTest

/// App Store screenshots, captured by fastlane (`bundle exec fastlane screenshots`).
/// Every screen is a fresh launch in demo mode that opens straight to it, so
/// nothing depends on tapping through localized UI.
final class AppStoreScreenshots: XCTestCase {
    /// In App Store order.
    private let screens = ["today", "nursing", "trends", "log", "growth", "diaper"]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshots() {
        for (index, screen) in screens.enumerated() {
            let app = XCUIApplication()
            setupSnapshot(app)
            app.launchArguments += ["-demoMode", "-demoScreen", screen]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
            snapshot(String(format: "%02d-%@", index + 1, screen), timeWaitingForIdle: 0)
            app.terminate()
        }
    }
}
