import Foundation

/// Countdown alarms on running timers ("let me know after 10 minutes").
public enum TimerAlarm {
    /// Kinds that can have a countdown alarm.
    public static let supportedKinds: [EventKind] = [.nursing, .bottle, .pumping, .activity, .sleep]

    /// Quick choices offered for each kind, in minutes.
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
