import Foundation

/// Countdown alarms on running timers ("let me know after 10 minutes").
public enum TimerAlarm {
    /// Kinds that can have a countdown alarm.
    public static let supportedKinds: [EventKind] = [.nursing, .bottle, .pumping, .activity, .sleep]

    /// The longest countdown that can be set, in minutes.
    public static let maxMinutes = 240

    /// How many quick choices a kind can have, so they still fit on a few lines.
    public static let maxPresets = 8

    /// Built-in quick choices for each kind, in minutes. People can change them
    /// in Settings → Timer Alarm.
    public static func presetMinutes(for kind: EventKind) -> [Int] {
        switch kind {
        case .nursing: return [5, 10, 15, 20, 30]
        case .bottle: return [5, 10, 15, 20, 30]
        case .pumping: return [10, 15, 20, 30]
        case .activity: return [3, 5, 10, 15, 30]
        case .sleep: return [20, 30, 45, 60, 90, 120]
        default: return []
        }
    }

    /// A countdown kept within 1…`maxMinutes`.
    public static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 1), maxMinutes)
    }

    /// Quick choices as they are kept: in range, no repeats, shortest first, and
    /// at most `maxPresets` of them.
    public static func normalizedPresets(_ minutes: [Int]) -> [Int] {
        Array(Set(minutes.filter { (1...maxMinutes).contains($0) }).sorted().prefix(maxPresets))
    }

    /// The pills to show: the quick choices plus the selected countdown when it
    /// was fine-tuned to something else (3 min nudged down to 2), in order.
    public static func choices(presets: [Int], selected: Int?) -> [Int] {
        guard let selected, !presets.contains(selected) else { return presets }
        return (presets + [selected]).sorted()
    }

    /// When the alarm for a running timer should ring, or nil when nothing should
    /// be scheduled (timer stopped, nursing paused, or the time has already passed).
    ///
    /// Nursing counts per side: the alarm rings when the active side reaches
    /// `duration`, and starts over when the side is switched.
    public static func fireDate(for record: EventRecord, after duration: TimeInterval, now: Date = Date()) -> Date? {
        guard duration > 0, record.isOngoing else { return nil }
        let date: Date
        if record.kind == .nursing {
            guard let side = record.activeSide, let since = record.activeSideStartedAt else { return nil }
            let banked = side == .left ? record.leftDuration : record.rightDuration
            date = since.addingTimeInterval(duration - banked)
        } else {
            date = record.startDate.addingTimeInterval(duration)
        }
        return date > now ? date : nil
    }
}
