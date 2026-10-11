import BabyCore
import Foundation

/// Identifiers and storage shared between the app and its widget extension.
/// The identifiers come from Info.plist, which takes them from Config/Shared.xcconfig.
enum SharedContainer {
    static let appGroupID: String = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        ?? "group.com.example.InfantTracker"

    static let cloudKitContainerID: String = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        ?? "iCloud.com.example.InfantTracker"

    static let defaults: UserDefaults = UserDefaults(suiteName: appGroupID) ?? .standard

    static var directory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var snapshotURL: URL { directory.appendingPathComponent("widget-snapshot.json") }

    static func loadSnapshot() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? WidgetSnapshotBuilder.decode(data) else { return .empty }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? WidgetSnapshotBuilder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }
}

/// User preferences, stored in the App Group so the widget sees the same values.
enum SettingsKey {
    static let selectedBabyID = "selectedBabyID"
    static let unitSystem = "unitSystem"
    static let temperatureUnit = "temperatureUnit"
    static let nightStartHour = "nightStartHour"
    static let nightEndHour = "nightEndHour"
    static let caregiverName = "caregiverName"
    static let feedReminderEnabled = "feedReminderEnabled"
    static let feedReminderHours = "feedReminderHours"
    static let diaperReminderEnabled = "diaperReminderEnabled"
    static let diaperReminderHours = "diaperReminderHours"
    static let napReminderEnabled = "napReminderEnabled"
    static let liveActivitiesEnabled = "liveActivitiesEnabled"
}

enum AppSettings {
    static var defaults: UserDefaults { SharedContainer.defaults }

    static var unitSystem: UnitSystem {
        defaults.string(forKey: SettingsKey.unitSystem).flatMap(UnitSystem.init(rawValue:))
            ?? (Locale.current.measurementSystem == .us ? .imperial : .metric)
    }

    static var temperatureUnit: TemperatureUnit {
        defaults.string(forKey: SettingsKey.temperatureUnit).flatMap(TemperatureUnit.init(rawValue:))
            ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius)
    }

    static var sleepClassifier: SleepClassifier {
        SleepClassifier(
            nightStartHour: defaults.object(forKey: SettingsKey.nightStartHour) as? Int ?? 19,
            nightEndHour: defaults.object(forKey: SettingsKey.nightEndHour) as? Int ?? 6
        )
    }

    static var selectedBabyID: UUID? {
        get { defaults.string(forKey: SettingsKey.selectedBabyID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: SettingsKey.selectedBabyID) }
    }

    static var caregiverName: String? {
        defaults.string(forKey: SettingsKey.caregiverName)?.nilIfBlankShared
    }

    static var liveActivitiesEnabled: Bool {
        defaults.object(forKey: SettingsKey.liveActivitiesEnabled) as? Bool ?? true
    }
}

extension String {
    fileprivate var nilIfBlankShared: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
