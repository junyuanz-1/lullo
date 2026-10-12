import AVFoundation
import BabyCore
import Foundation
import OSLog
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
#endif

/// Gentle sounds bundled in App/Resources/Sounds.
enum AlarmSound: String, CaseIterable, Identifiable {
    case chime = "Chime"
    case musicBox = "MusicBox"
    case harp = "Harp"
    case windChimes = "WindChimes"

    var id: String { rawValue }
    var fileName: String { "\(rawValue).wav" }

    var title: String {
        switch self {
        case .chime: return String(localized: "Soft Chime")
        case .musicBox: return String(localized: "Music Box")
        case .harp: return String(localized: "Harp")
        case .windChimes: return String(localized: "Wind Chimes")
        }
    }
}

/// Countdown alarms on running timers. The chosen countdown is a setting on
/// this phone only (a partner's phone does not ring). Alarms are reconciled
/// from the running timers after every change, so switching sides or stopping
/// from the Lock Screen moves or cancels them automatically.
///
/// On iOS 26 and later they are real alarms (AlarmKit) that ring even in
/// Silent mode; earlier versions use a notification with the same sound.
@MainActor
final class TimerAlarms: ObservableObject {
    static let shared = TimerAlarms()

    @Published private(set) var durations: [UUID: TimeInterval]
    var sound: AlarmSound {
        defaults.string(forKey: SettingsKey.alarmSound).flatMap(AlarmSound.init(rawValue:)) ?? .chime
    }

    private let defaults = SharedContainer.defaults
    private static let durationsKey = "timerAlarmDurations"
    private let scheduledKey = "timerAlarmScheduled"
    private let logger = Logger(subsystem: "Tinytide", category: "TimerAlarms")
    private var preview: AVAudioPlayer?

    init() {
        let stored = SharedContainer.defaults.dictionary(forKey: Self.durationsKey) as? [String: Double] ?? [:]
        durations = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    // MARK: Settings

    func duration(for eventID: UUID?) -> TimeInterval? {
        eventID.flatMap { durations[$0] }
    }

    /// Sets (or with nil, clears) the countdown for a running timer.
    func setDuration(_ duration: TimeInterval?, for eventID: UUID) {
        durations[eventID] = duration
        saveDurations()
        TrackerStore.shared.scheduleSideEffects()
        if duration != nil {
            Task {
                await requestAuthorization()
                // The first sync ran while the permission prompt was still up, when
                // the alarm couldn't be scheduled; forget it so it is scheduled now.
                forgetScheduled(eventID)
                TrackerStore.shared.scheduleSideEffects()
            }
        }
    }

    private func forgetScheduled(_ eventID: UUID) {
        var scheduled = defaults.dictionary(forKey: scheduledKey) as? [String: Double] ?? [:]
        scheduled[eventID.uuidString] = nil
        defaults.set(scheduled, forKey: scheduledKey)
    }

    /// The countdown last chosen for this kind, offered again next time.
    func lastUsed(for kind: EventKind) -> TimeInterval? {
        let value = defaults.double(forKey: "timerAlarmLast.\(kind.rawValue)")
        return value > 0 ? value : nil
    }

    func rememberLastUsed(_ duration: TimeInterval?, for kind: EventKind) {
        defaults.set(duration ?? 0, forKey: "timerAlarmLast.\(kind.rawValue)")
    }

    /// The countdown pills offered for this kind: the ones set up in Settings,
    /// or the built-in ones.
    func presetMinutes(for kind: EventKind) -> [Int] {
        customPresets(for: kind) ?? TimerAlarm.presetMinutes(for: kind)
    }

    func hasCustomPresets(for kind: EventKind) -> Bool {
        customPresets(for: kind) != nil
    }

    /// Saves the pills for this kind; nil goes back to the built-in ones.
    func setPresetMinutes(_ minutes: [Int]?, for kind: EventKind) {
        objectWillChange.send()
        let key = "timerAlarmPresets.\(kind.rawValue)"
        if let minutes {
            defaults.set(TimerAlarm.normalizedPresets(minutes), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func customPresets(for kind: EventKind) -> [Int]? {
        (defaults.array(forKey: "timerAlarmPresets.\(kind.rawValue)") as? [Int]).map(TimerAlarm.normalizedPresets)
    }

    func fireDate(for record: EventRecord, now: Date = Date()) -> Date? {
        guard let duration = durations[record.id] else { return nil }
        return TimerAlarm.fireDate(for: record, after: duration, now: now)
    }

    private func saveDurations() {
        defaults.set(Dictionary(uniqueKeysWithValues: durations.map { ($0.key.uuidString, $0.value) }), forKey: Self.durationsKey)
    }

    // MARK: Scheduling

    /// Brings scheduled alarms in line with the running timers.
    func sync(running: [EventRecord], babyNames: [UUID: String], now: Date = Date()) {
        let runningIDs = Set(running.map(\.id))
        let finished = durations.keys.filter { !runningIDs.contains($0) }
        if !finished.isEmpty {
            finished.forEach { durations[$0] = nil }
            saveDurations()
        }

        var scheduled = (defaults.dictionary(forKey: scheduledKey) as? [String: Double] ?? [:])
        var wanted: [String: (EventRecord, Date)] = [:]
        for record in running {
            if let date = fireDate(for: record, now: now) { wanted[record.id.uuidString] = (record, date) }
        }
        for (id, _) in scheduled where wanted[id] == nil {
            cancel(id)
            scheduled[id] = nil
        }
        for (id, (record, date)) in wanted {
            if let existing = scheduled[id], abs(existing - date.timeIntervalSince1970) < 1 { continue }
            cancel(id)
            schedule(record: record, babyName: babyNames[record.babyID] ?? "", at: date)
            scheduled[id] = date.timeIntervalSince1970
        }
        defaults.set(scheduled, forKey: scheduledKey)
    }

    private func schedule(record: EventRecord, babyName: String, at date: Date) {
        let title = alarmTitle(for: record)
        let body = String(localized: "\(babyName): \(Fmt.duration(durations[record.id] ?? 0)) is up.")
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
            let id = record.id
            let tint = record.kind.color
            let soundFile = sound.fileName
            Task {
                do {
                    try await AlarmKitBackend.schedule(id: id, title: title, tint: tint, sound: soundFile, at: date)
                } catch {
                    logger.error("AlarmKit failed, using a notification: \(error.localizedDescription)")
                    scheduleNotification(id: id.uuidString, title: title, body: body, at: date)
                }
            }
            return
        }
        #endif
        scheduleNotification(id: record.id.uuidString, title: title, body: body, at: date)
    }

    private func scheduleNotification(id: String, title: String, body: String, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "alarm-\(id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm-\(id)"])
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let uuid = UUID(uuidString: id) {
            AlarmKitBackend.cancel(id: uuid)
        }
        #endif
    }

    private func alarmTitle(for record: EventRecord) -> String {
        switch record.kind {
        case .nursing: return String(localized: "Time’s up on this side")
        case .sleep: return String(localized: "Nap Alarm")
        default: return String(localized: "\(record.displayTitle) timer is up")
        }
    }

    // MARK: Permission and preview

    func requestAuthorization() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            if AlarmManager.shared.authorizationState == .notDetermined {
                _ = try? await AlarmManager.shared.requestAuthorization()
            }
            if AlarmManager.shared.authorizationState == .authorized { return }
        }
        #endif
        _ = await NotificationManager.requestAuthorization()
    }

    /// Plays a sound once so it can be chosen in Settings.
    func playPreview(_ sound: AlarmSound) {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        preview = try? AVAudioPlayer(contentsOf: url)
        preview?.play()
    }

    func stopPreview() {
        preview?.stop()
        preview = nil
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct TimerAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
private enum AlarmKitBackend {
    static func schedule(id: UUID, title: String, tint: Color, sound: String, at date: Date) async throws {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "OK", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<TimerAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: TimerAlarmMetadata(),
            tintColor: tint
        )
        let configuration = AlarmManager.AlarmConfiguration<TimerAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .named(sound)
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func cancel(id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }
}
#endif
