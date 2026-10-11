import Foundation

/// A small, precomputed summary the app writes into the shared App Group
/// container so widgets and Live Activities can render without opening the
/// database.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var selectedBabyID: UUID?
    public var babies: [BabySnapshot]
    public var unitSystem: UnitSystem

    public init(generatedAt: Date = Date(), selectedBabyID: UUID?, babies: [BabySnapshot], unitSystem: UnitSystem) {
        self.generatedAt = generatedAt
        self.selectedBabyID = selectedBabyID
        self.babies = babies
        self.unitSystem = unitSystem
    }

    public static let empty = WidgetSnapshot(generatedAt: .distantPast, selectedBabyID: nil, babies: [], unitSystem: .metric)

    public func baby(_ id: UUID?) -> BabySnapshot? {
        if let id, let match = babies.first(where: { $0.id == id }) { return match }
        if let selectedBabyID, let match = babies.first(where: { $0.id == selectedBabyID }) { return match }
        return babies.first
    }
}

public struct BabySnapshot: Codable, Equatable, Sendable, Identifiable {
    public struct LastFeed: Codable, Equatable, Sendable {
        public var date: Date
        public var kind: EventKind
        public var amountML: Double?
        public var side: BreastSide?
        public var duration: TimeInterval?
    }

    public struct LastDiaper: Codable, Equatable, Sendable {
        public var date: Date
        public var type: DiaperType
    }

    public struct RunningTimer: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var kind: EventKind
        public var startDate: Date
        public var activityType: ActivityType?
        // Nursing only
        public var activeSide: BreastSide?
        public var activeSideStartedAt: Date?
        public var leftDuration: TimeInterval
        public var rightDuration: TimeInterval
    }

    public struct Today: Codable, Equatable, Sendable {
        public var sleep: TimeInterval
        public var feeds: Int
        public var bottleML: Double
        public var wetDiapers: Int
        public var dirtyDiapers: Int
    }

    public var id: UUID
    public var name: String
    public var birthDate: Date
    public var lastFeed: LastFeed?
    public var lastDiaper: LastDiaper?
    /// End of the most recent sleep, when the baby is awake.
    public var awakeSince: Date?
    public var runningTimers: [RunningTimer]
    public var nextNap: NapPrediction?
    public var suggestedSide: BreastSide
    public var today: Today

    public var runningSleep: RunningTimer? { runningTimers.first { $0.kind == .sleep } }
    public var runningNursing: RunningTimer? { runningTimers.first { $0.kind == .nursing } }
}

public enum WidgetSnapshotBuilder {
    /// - Parameter events: this baby's recent events (a few days is plenty).
    public static func make(
        baby: BabyRecord,
        events: [EventRecord],
        now: Date = Date(),
        classifier: SleepClassifier = SleepClassifier(),
        calendar: Calendar = .current
    ) -> BabySnapshot {
        let mine = events.filter { $0.babyID == baby.id }.sorted { $0.startDate < $1.startDate }

        let lastFeed = mine.last(where: { $0.kind.isFeeding }).map { e in
            BabySnapshot.LastFeed(
                date: e.startDate,
                kind: e.kind,
                amountML: e.amountML,
                side: e.lastSide ?? e.activeSide,
                duration: e.kind == .nursing ? e.nursingTotal(at: now) : nil
            )
        }
        let lastDiaper = mine.last(where: { $0.kind == .diaper && $0.diaperType != nil }).map {
            BabySnapshot.LastDiaper(date: $0.startDate, type: $0.diaperType!)
        }

        let sleeps = mine.filter { $0.kind == .sleep }
        let sleeping = sleeps.contains { $0.isOngoing }
        let awakeSince = sleeping ? nil : sleeps.compactMap(\.endDate).max()

        let timers = mine.filter(\.isOngoing).map { e in
            BabySnapshot.RunningTimer(
                id: e.id,
                kind: e.kind,
                startDate: e.startDate,
                activityType: e.activityType,
                activeSide: e.activeSide,
                activeSideStartedAt: e.activeSideStartedAt,
                leftDuration: e.leftDuration,
                rightDuration: e.rightDuration
            )
        }

        let lastNursing = mine.last(where: { $0.kind == .nursing })
        let todaySummary = Statistics.dailySummaries(
            events: mine, from: now, to: now, now: now, classifier: classifier, calendar: calendar
        ).first ?? DailySummary(day: calendar.startOfDay(for: now))

        return BabySnapshot(
            id: baby.id,
            name: baby.name,
            birthDate: baby.birthDate,
            lastFeed: lastFeed,
            lastDiaper: lastDiaper,
            awakeSince: awakeSince,
            runningTimers: timers,
            nextNap: sleeping ? nil : NapPredictor.predict(
                birthDate: baby.birthDate, sleeps: sleeps, now: now, classifier: classifier, calendar: calendar
            ),
            suggestedSide: EventRecord.suggestedNextSide(after: lastNursing),
            today: .init(
                sleep: todaySummary.totalSleep,
                feeds: todaySummary.feedCount,
                bottleML: todaySummary.bottleVolumeML,
                wetDiapers: todaySummary.wetDiapers,
                dirtyDiapers: todaySummary.dirtyDiapers
            )
        )
    }

    public static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}

extension BabySnapshot {
    /// Sample data for widget placeholders and previews.
    public static func preview(now: Date = Date()) -> BabySnapshot {
        let baby = BabyRecord(name: "Mia", birthDate: now.addingTimeInterval(-120 * 86_400), sex: .female)
        let events = [
            EventRecord(babyID: baby.id, kind: .sleep, startDate: now.addingTimeInterval(-3 * 3600), endDate: now.addingTimeInterval(-50 * 60)),
            EventRecord(babyID: baby.id, kind: .bottle, startDate: now.addingTimeInterval(-2 * 3600), amountML: 120, bottleContent: .formula),
            EventRecord(babyID: baby.id, kind: .diaper, startDate: now.addingTimeInterval(-3600), diaperType: .wet),
        ]
        return WidgetSnapshotBuilder.make(baby: baby, events: events, now: now)
    }
}
