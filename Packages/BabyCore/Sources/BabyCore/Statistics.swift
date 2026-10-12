import Foundation

/// Decides whether a sleep counts as a nap or as night sleep, based on the hour
/// it started.
public struct SleepClassifier: Codable, Equatable, Sendable {
    /// Sleeps starting at or after this hour count as night sleep.
    public var nightStartHour: Int
    /// Sleeps starting before this hour count as night sleep.
    public var nightEndHour: Int

    public init(nightStartHour: Int = 19, nightEndHour: Int = 6) {
        self.nightStartHour = nightStartHour
        self.nightEndHour = nightEndHour
    }

    public func isNight(_ start: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: start)
        return hour >= nightStartHour || hour < nightEndHour
    }
}

public struct DailySummary: Equatable, Sendable, Identifiable {
    public var day: Date
    public var id: Date { day }

    public var totalSleep: TimeInterval = 0
    public var napSleep: TimeInterval = 0
    public var nightSleep: TimeInterval = 0
    public var napCount = 0
    public var longestSleep: TimeInterval = 0

    public var feedCount = 0
    public var nursingCount = 0
    public var nursingDuration: TimeInterval = 0
    public var bottleCount = 0
    public var bottleVolumeML: Double = 0
    public var solidsCount = 0

    public var pumpingCount = 0
    public var pumpingVolumeML: Double = 0

    public var diaperCount = 0
    public var wetDiapers = 0
    public var dirtyDiapers = 0

    public var activityDuration: [ActivityType: TimeInterval] = [:]

    public init(day: Date) {
        self.day = day
    }

    public var hasData: Bool {
        totalSleep > 0 || feedCount > 0 || diaperCount > 0 || pumpingCount > 0
    }
}

/// One day's row in the 24-hour schedule chart. Offsets are seconds since the
/// start of the day.
public struct DaySchedule: Equatable, Sendable, Identifiable {
    public struct Block: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var kind: EventKind
    }

    public struct Mark: Equatable, Sendable {
        public var offset: TimeInterval
        public var kind: EventKind
    }

    public var day: Date
    public var id: Date { day }
    public var dayLength: TimeInterval
    public var blocks: [Block]
    public var marks: [Mark]
}

public enum Statistics {
    /// Builds one summary per calendar day in `[from, to]` (inclusive, by day).
    /// Sleep that spans midnight is split across the days it overlaps.
    public static func dailySummaries(
        events: [EventRecord],
        from: Date,
        to: Date,
        now: Date = Date(),
        classifier: SleepClassifier = SleepClassifier(),
        calendar: Calendar = .current
    ) -> [DailySummary] {
        let days = self.days(from: from, to: to, calendar: calendar)
        guard !days.isEmpty else { return [] }
        var summaries = days.map { DailySummary(day: $0) }
        var index: [Date: Int] = [:]
        for (i, day) in days.enumerated() { index[day] = i }

        for event in events {
            let dayOfStart = calendar.startOfDay(for: event.startDate)
            switch event.kind {
            case .sleep:
                let end = event.effectiveEnd(at: now)
                let isNight = classifier.isNight(event.startDate, calendar: calendar)
                if let i = index[dayOfStart], !isNight {
                    summaries[i].napCount += 1
                }
                for (day, overlap) in overlaps(start: event.startDate, end: end, calendar: calendar) {
                    guard let i = index[day] else { continue }
                    summaries[i].totalSleep += overlap
                    if isNight { summaries[i].nightSleep += overlap } else { summaries[i].napSleep += overlap }
                }
                if let i = index[dayOfStart] {
                    summaries[i].longestSleep = max(summaries[i].longestSleep, end.timeIntervalSince(event.startDate))
                }
            case .nursing:
                guard let i = index[dayOfStart] else { continue }
                summaries[i].feedCount += 1
                summaries[i].nursingCount += 1
                summaries[i].nursingDuration += event.nursingTotal(at: now)
            case .bottle:
                guard let i = index[dayOfStart] else { continue }
                summaries[i].feedCount += 1
                summaries[i].bottleCount += 1
                summaries[i].bottleVolumeML += event.amountML ?? 0
            case .solids:
                guard let i = index[dayOfStart] else { continue }
                summaries[i].feedCount += 1
                summaries[i].solidsCount += 1
            case .pumping:
                guard let i = index[dayOfStart] else { continue }
                summaries[i].pumpingCount += 1
                summaries[i].pumpingVolumeML += event.pumpedTotalML ?? 0
            case .diaper:
                guard let i = index[dayOfStart], let type = event.diaperType else { continue }
                summaries[i].diaperCount += 1
                if type.isWet { summaries[i].wetDiapers += 1 }
                if type.isDirty { summaries[i].dirtyDiapers += 1 }
            case .activity:
                guard let i = index[dayOfStart] else { continue }
                let type = event.activityType ?? .other
                summaries[i].activityDuration[type, default: 0] += event.duration(at: now)
            case .growth, .medication, .temperature, .symptom, .vaccine, .note:
                continue
            }
        }
        return summaries
    }

    /// Per-day rows for the 24 h schedule chart (sleep and feeding blocks, diaper marks).
    public static func schedules(
        events: [EventRecord],
        from: Date,
        to: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DaySchedule] {
        let days = self.days(from: from, to: to, calendar: calendar)
        var rows = days.map { day -> DaySchedule in
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return DaySchedule(day: day, dayLength: next.timeIntervalSince(day), blocks: [], marks: [])
        }
        var index: [Date: Int] = [:]
        for (i, day) in days.enumerated() { index[day] = i }

        for event in events {
            // A bottle timed for at least a minute is drawn as a block; a bottle
            // logged without a duration stays a tick.
            let timedBottle = event.kind == .bottle && event.duration(at: now) >= 60
            switch event.kind {
            case .sleep, .nursing, .pumping, .bottle where timedBottle:
                // Nursing is drawn from its start for its summed duration; good enough for a schedule view.
                let end = event.kind == .nursing
                    ? event.startDate.addingTimeInterval(max(event.nursingTotal(at: now), 60))
                    : event.effectiveEnd(at: now)
                for (day, _) in overlaps(start: event.startDate, end: end, calendar: calendar) {
                    guard let i = index[day] else { continue }
                    let dayStart = rows[i].day
                    let s = max(0, event.startDate.timeIntervalSince(dayStart))
                    let e = min(rows[i].dayLength, end.timeIntervalSince(dayStart))
                    if e > s { rows[i].blocks.append(.init(start: s, end: e, kind: event.kind)) }
                }
            case .bottle, .solids, .diaper, .medication:
                let day = calendar.startOfDay(for: event.startDate)
                guard let i = index[day] else { continue }
                rows[i].marks.append(.init(offset: event.startDate.timeIntervalSince(day), kind: event.kind))
            default:
                continue
            }
        }
        return rows
    }

    /// Averages of the days that actually contain data.
    public static func average(_ summaries: [DailySummary]) -> DailySummary? {
        let withData = summaries.filter(\.hasData)
        guard let first = withData.first else { return nil }
        let n = Double(withData.count)
        var avg = DailySummary(day: first.day)
        avg.totalSleep = withData.map(\.totalSleep).reduce(0, +) / n
        avg.napSleep = withData.map(\.napSleep).reduce(0, +) / n
        avg.nightSleep = withData.map(\.nightSleep).reduce(0, +) / n
        avg.napCount = Int((Double(withData.map(\.napCount).reduce(0, +)) / n).rounded())
        avg.longestSleep = withData.map(\.longestSleep).reduce(0, +) / n
        avg.feedCount = Int((Double(withData.map(\.feedCount).reduce(0, +)) / n).rounded())
        avg.nursingDuration = withData.map(\.nursingDuration).reduce(0, +) / n
        avg.bottleVolumeML = withData.map(\.bottleVolumeML).reduce(0, +) / n
        avg.pumpingVolumeML = withData.map(\.pumpingVolumeML).reduce(0, +) / n
        avg.diaperCount = Int((Double(withData.map(\.diaperCount).reduce(0, +)) / n).rounded())
        avg.wetDiapers = Int((Double(withData.map(\.wetDiapers).reduce(0, +)) / n).rounded())
        avg.dirtyDiapers = Int((Double(withData.map(\.dirtyDiapers).reduce(0, +)) / n).rounded())
        return avg
    }

    static func days(from: Date, to: Date, calendar: Calendar) -> [Date] {
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: to)
        var result: [Date] = []
        while day <= last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Splits `[start, end)` into per-day overlaps.
    static func overlaps(start: Date, end: Date, calendar: Calendar) -> [(Date, TimeInterval)] {
        guard end > start else { return [] }
        var result: [(Date, TimeInterval)] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let overlap = min(end, next).timeIntervalSince(max(start, day))
            if overlap > 0 { result.append((day, overlap)) }
            day = next
        }
        return result
    }
}
