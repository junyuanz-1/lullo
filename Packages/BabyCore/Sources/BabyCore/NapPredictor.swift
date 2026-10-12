import Foundation

public struct WakeWindow: Equatable, Sendable {
    public var min: TimeInterval
    public var max: TimeInterval

    public init(min: TimeInterval, max: TimeInterval) {
        self.min = min
        self.max = max
    }

    public var center: TimeInterval { (min + max) / 2 }
    public var width: TimeInterval { max - min }
}

/// A suggested window for the next sleep (the "sweet spot").
public struct NapPrediction: Codable, Equatable, Sendable {
    public var awakeSince: Date
    public var earliest: Date
    public var latest: Date
    /// The suggested sleep falls in the night window, so it is bedtime rather than a nap.
    public var isBedtime: Bool
    /// Adjusted using this baby's own recent wake windows.
    public var isPersonalized: Bool

    public init(awakeSince: Date, earliest: Date, latest: Date, isBedtime: Bool, isPersonalized: Bool) {
        self.awakeSince = awakeSince
        self.earliest = earliest
        self.latest = latest
        self.isBedtime = isBedtime
        self.isPersonalized = isPersonalized
    }
}

/// Age-based wake-window guidance, optionally personalised with the baby's own
/// recent pattern. This is a rough guide, not medical advice.
public enum NapPredictor {
    /// (age upper bound in months, wake window min/max in minutes)
    static let wakeWindows: [(upTo: Double, min: Double, max: Double)] = [
        (1, 35, 60),
        (2, 50, 80),
        (3, 60, 90),
        (4, 75, 105),
        (5, 90, 135),
        (6, 120, 150),
        (7, 120, 165),
        (8, 135, 180),
        (9, 150, 195),
        (10, 150, 210),
        (11, 165, 225),
        (12, 180, 240),
        (15, 180, 270),
        (18, 240, 330),
        (.infinity, 300, 360),
    ]

    public static func typicalWakeWindow(ageInMonths age: Double) -> WakeWindow {
        let row = wakeWindows.first { age < $0.upTo } ?? wakeWindows[wakeWindows.count - 1]
        return WakeWindow(min: row.min * 60, max: row.max * 60)
    }

    /// Recommended total sleep per 24 h, in hours (AASM / NSF guidance).
    public static func recommendedDailySleepHours(ageInMonths age: Double) -> ClosedRange<Double> {
        switch age {
        case ..<4: return 14...17
        case ..<12: return 12...16
        case ..<36: return 11...14
        default: return 10...13
        }
    }

    /// Daytime gaps between the end of one sleep and the start of the next nap.
    public static func observedWakeWindows(
        sleeps: [EventRecord],
        since: Date,
        classifier: SleepClassifier,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimeInterval] {
        let sorted = sleeps.filter { $0.kind == .sleep }.sorted { $0.startDate < $1.startDate }
        var result: [TimeInterval] = []
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            guard let end = previous.endDate, end >= since else { continue }
            // By start hour, not overlap: a sleep resumed after a night waking
            // (04:40–08:00) is mostly outside the night window, but the gap before
            // it is a night waking, not a daytime wake window.
            guard !classifier.isNight(next.startDate, calendar: calendar) else { continue }
            let gap = next.startDate.timeIntervalSince(end)
            if gap >= 10 * 60 && gap <= 8 * 3600 { result.append(gap) }
        }
        return result
    }

    public static func predict(
        birthDate: Date,
        sleeps: [EventRecord],
        now: Date = Date(),
        classifier: SleepClassifier = SleepClassifier(),
        calendar: Calendar = .current
    ) -> NapPrediction? {
        let sorted = sleeps.filter { $0.kind == .sleep }.sorted { $0.startDate < $1.startDate }
        guard let last = sorted.last, let awakeSince = last.endDate else { return nil }
        guard now.timeIntervalSince(awakeSince) < 12 * 3600 else { return nil }

        let age = max(0, awakeSince.timeIntervalSince(birthDate) / (86_400 * 30.4375))
        var window = typicalWakeWindow(ageInMonths: age)

        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let observed = observedWakeWindows(sleeps: sorted, since: weekAgo, classifier: classifier, now: now, calendar: calendar)
        let personalized = observed.count >= 5
        if personalized {
            let median = observed.sorted()[observed.count / 2]
            let center = (window.center + median) / 2
            window = WakeWindow(min: max(15 * 60, center - window.width / 2), max: center + window.width / 2)
        }

        // Later wake windows in the day tend to be longer.
        let dayStart = calendar.startOfDay(for: awakeSince)
        let napsToday = sorted.filter {
            $0.startDate >= dayStart && $0.startDate <= awakeSince && !classifier.isNight($0.startDate, calendar: calendar)
        }.count
        let t = min(0.5, 0.2 * Double(napsToday))
        let earliest = awakeSince.addingTimeInterval(window.min + window.width * t)
        let latest = earliest.addingTimeInterval(window.width * 0.5)

        return NapPrediction(
            awakeSince: awakeSince,
            earliest: earliest,
            latest: latest,
            isBedtime: classifier.isNight(earliest, calendar: calendar),
            isPersonalized: personalized
        )
    }
}
