import BabyCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Tinytide

/// Renders the main screens with the demo week and compares them to the
/// reference images in __Snapshots__. A failure means the UI changed: look at
/// the diff (CI uploads it), then either fix the regression or re-record with
/// the "Record snapshots" workflow (or `scripts/snapshots.sh record`).
///
/// Run per language with `xcodebuild test -testLanguage <code>`. Every language
/// gets the light-mode images; English also gets dark mode and the largest
/// accessibility text size.
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    private var store: TrackerStore!
    private var baby: Baby!

    /// Sunday 15 March 2026, 9:41 UTC.
    private static let now = Date(timeIntervalSince1970: 1_773_567_660)

    override func setUp() async throws {
        NSTimeZone.default = TimeZone(identifier: "UTC")!
        AppClock.fixed = Self.now
        let defaults = SharedContainer.defaults
        defaults.set(UnitSystem.metric.rawValue, forKey: SettingsKey.unitSystem)
        defaults.set(TemperatureUnit.celsius.rawValue, forKey: SettingsKey.temperatureUnit)
        defaults.removeObject(forKey: Appearance.themeKey)
        defaults.removeObject(forKey: SettingsKey.caregiverName)

        store = TrackerStore(persistence: PersistenceController(inMemory: true))
        baby = DemoMode.seed(into: store, now: Self.now)
    }

    override func tearDown() async throws {
        AppClock.fixed = nil
        store = nil
        baby = nil
    }

    // MARK: Tabs

    func testToday() {
        // The largest text size needs the extra height to reach the quick actions.
        verify(HomeView(baby: baby), height: 1500, xxxlHeight: 3600)
    }

    func testLog() {
        verify(HistoryView(baby: baby), height: 1200)
    }

    func testTrends() {
        verify(TrendsView(baby: baby), height: 2300)
    }

    func testGrowth() {
        verify(GrowthView(baby: baby), height: 1100)
    }

    func testMore() {
        verify(SettingsView(), height: 2600)
    }

    func testAppearance() {
        verify(NavigationStack { AppearanceView() })
    }

    // MARK: Editors

    func testNewNursing() {
        verify(editor(.nursing))
    }

    func testRunningNursing() throws {
        let running = try XCTUnwrap(store.runningTimer(.nursing, for: baby))
        verify(editor(.nursing, existing: running), height: 1000)
    }

    func testNewSleep() {
        verify(editor(.sleep))
    }

    func testNewDiaper() {
        verify(editor(.diaper), height: 1000)
    }

    func testNewBottle() {
        verify(editor(.bottle))
    }

    func testNewGrowth() {
        verify(editor(.growth))
    }

    func testNewActivity() {
        verify(editor(.activity))
    }

    // MARK: Helpers

    private func editor(_ kind: EventKind, existing: Event? = nil) -> some View {
        NavigationStack {
            EventEditorView(baby: baby, kind: kind, existing: existing)
        }
    }

    private var language: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    private func verify(
        _ view: some View,
        height: CGFloat = 844,
        xxxlHeight: CGFloat? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let screen = view
            .environment(\.managedObjectContext, store.context)
            .environmentObject(store)
            .environmentObject(SyncMonitor(persistence: store.persistence))
            .tint(AppTheme.lullaby.color)

        var variants: [(name: String, traits: UITraitCollection, height: CGFloat)] = [("light", Self.traits(.light), height)]
        if language == "en" {
            variants.append(("dark", Self.traits(.dark), height))
            variants.append(("xxxl", Self.traits(.light, text: .accessibilityExtraExtraLarge), xxxlHeight ?? height))
        }
        for variant in variants {
            assertSnapshot(
                of: screen,
                as: .image(
                    precision: 0.995,
                    perceptualPrecision: 0.98,
                    layout: .fixed(width: 390, height: variant.height),
                    traits: variant.traits
                ),
                named: "\(language)-\(variant.name)",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    private static func traits(_ style: UIUserInterfaceStyle, text: UIContentSizeCategory = .large) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: 2),
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(preferredContentSizeCategory: text),
        ])
    }
}
