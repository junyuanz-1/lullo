import BabyCore
import Foundation

/// Identifiers and storage shared between the app and its widget extension.
/// The identifiers come from Info.plist, which takes them from Config/Shared.xcconfig.
enum SharedContainer {
    static let appGroupID: String = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        ?? "group.app.tinytide.ios"

    static let cloudKitContainerID: String = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        ?? "iCloud.app.tinytide.ios"

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
    static let alarmSound = "alarmSound"
    static let nightStartHour = "nightStartHour"
    static let nightEndHour = "nightEndHour"
    static let caregiverName = "caregiverName"
    static let feedReminderEnabled = "feedReminderEnabled"
    static let feedReminderHours = "feedReminderHours"
    static let diaperReminderEnabled = "diaperReminderEnabled"
    static let diaperReminderHours = "diaperReminderHours"
    static let napReminderEnabled = "napReminderEnabled"
    static let liveActivitiesEnabled = "liveActivitiesEnabled"
    static let initialCloudImportDone = "initialCloudImportDone"
    static let cloudAccountAvailable = "cloudAccountAvailable"
    static let firstCloudImportWaitStart = "firstCloudImportWaitStart"
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

    /// Set once iCloud has finished a first download of this user's own data on
    /// this device; cleared when the iCloud account changes.
    static var initialCloudImportDone: Bool {
        get { defaults.bool(forKey: SettingsKey.initialCloudImportDone) }
        set { defaults.set(newValue, forKey: SettingsKey.initialCloudImportDone) }
    }

    /// Whether CloudKit last reported a usable iCloud account.
    static var cloudAccountAvailable: Bool {
        get { defaults.bool(forKey: SettingsKey.cloudAccountAvailable) }
        set { defaults.set(newValue, forKey: SettingsKey.cloudAccountAvailable) }
    }

    /// When this device started waiting for its first download.
    static var firstCloudImportWaitStart: Date? {
        get { defaults.object(forKey: SettingsKey.firstCloudImportWaitStart) as? Date }
        set { defaults.set(newValue, forKey: SettingsKey.firstCloudImportWaitStart) }
    }

    /// True while a device with iCloud may still be downloading its data (fresh
    /// install, new phone): a backup taken now would hold only part of it, and an
    /// import could add a second copy of a baby that is about to arrive. Never
    /// for more than 3 days, so a device whose sync never completes (iCloud off
    /// for this app, persistent errors) still gets its daily backups.
    static var awaitingFirstCloudImport: Bool {
        guard cloudAccountAvailable, !initialCloudImportDone else { return false }
        guard let start = firstCloudImportWaitStart else { return true }
        return Date().timeIntervalSince(start) < 3 * 86_400
    }
}

extension String {
    fileprivate var nilIfBlankShared: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
