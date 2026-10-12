import BabyCore
import Foundation

/// Launch with `-demoMode` (App Store screenshots, UI tests) to get an
/// in-memory store filled with a realistic week, the clock pinned to 9:41 today
/// and nothing synced to iCloud. `-demoScreen <name>` opens a given screen.
enum DemoMode {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demoMode")

    enum Screen: String {
        case today, log, trends, growth, more
        case nursing, diaper, bottle
        case tipjar, supporter
    }

    /// The purchase screens, opened from Settings for the App Review screenshots.
    enum PurchaseScreen: Hashable {
        case tipJar, supporter
    }

    static var screen: Screen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isEnabled, let index = arguments.firstIndex(of: "-demoScreen"), index + 1 < arguments.count else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }

    /// The tab to open at launch.
    static var initialTab: RootTab {
        switch screen {
        case .log: return .log
        case .trends: return .trends
        case .growth: return .growth
        case .more, .tipjar, .supporter: return .more
        default: return .today
        }
    }

    /// The new-entry sheet to show on top of Today at launch.
    static var initialEditor: EventKind? {
        switch screen {
        case .nursing: return .nursing
        case .diaper: return .diaper
        case .bottle: return .bottle
        default: return nil
        }
    }

    /// The purchase screen to open in Settings at launch.
    static var initialPurchaseScreen: PurchaseScreen? {
        switch screen {
        case .tipjar: return .tipJar
        case .supporter: return .supporter
        default: return nil
        }
    }

    /// 9:41 today, like Apple's own screenshots.
    static var now: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }

    /// Called once at launch in demo mode, before any view appears.
    @MainActor
    static func start() {
        AppClock.fixed = now
        // Start from the defaults for the simulator's language and region.
        for key in [SettingsKey.unitSystem, SettingsKey.temperatureUnit, Appearance.themeKey, SettingsKey.caregiverName] {
            SharedContainer.defaults.removeObject(forKey: key)
        }
        seed(into: TrackerStore.shared, now: now)
    }

    /// Fills `store` with the demo week. Saves without the usual side effects, so
    /// no Live Activity, widget refresh or reminder is triggered.
    @MainActor
    @discardableResult
    static func seed(into store: TrackerStore, now: Date) -> Baby {
        let data = DemoData.make(
            name: String(localized: "Mia", comment: "Name of the sample baby in demo mode and App Store screenshots"),
            note: String(localized: "First real laugh! 😄", comment: "Sample note in demo mode"),
            now: now
        )
        let baby = store.persistence.newBaby(in: store.context)
        baby.apply(data.baby)
        for record in data.events {
            store.persistence.newEvent(for: baby, in: store.context).apply(record)
        }
        store.persistence.save()
        store.selectedBabyID = data.baby.id
        return baby
    }
}
