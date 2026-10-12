import Foundation

/// A realistic week for a three-month-old, used for App Store screenshots and
/// snapshot tests. Deterministic: the same `now` always gives the same data.
public enum DemoData {
    public struct Dataset: Sendable {
        public var baby: BabyRecord
        public var events: [EventRecord]
    }

    public static func make(
        name: String = "Mia",
        note: String = "First real laugh! 😄",
        now: Date,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> Dataset {
        let today = calendar.startOfDay(for: now)
        let birth = calendar.date(byAdding: .day, value: -98, to: today)!.addingTimeInterval(4 * 3600 + 12 * 60)
        let baby = BabyRecord(
            id: uuid(0, 0),
            name: name,
            birthDate: birth,
            sex: .female,
            createdAt: birth,
            updatedAt: birth
        )
        var builder = Builder(babyID: baby.id, now: now)

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let jitter = Double((dayOffset * 7) % 5 - 2) * 5 * 60 // ±10 min, varies by day
            func at(_ hour: Int, _ minute: Int) -> Date {
                day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60) + jitter)
            }

            // Night (from the evening before), with two wake-ups for feeds.
            builder.sleep(at(-4, -30), at(-1, -20)) // 19:30 – 22:40
            builder.nursing(at(-1, -10), left: 9, right: 7, endingOn: .right)
            builder.sleep(at(-0, -50), at(3, 5))
            builder.nursing(at(3, 15), left: 11, right: 0, endingOn: .left)
            builder.diaper(at(3, 40), .wet, pee: .large)
            builder.sleep(at(3, 50), at(6, 45))

            // Day.
            builder.nursing(at(6, 50), left: 8, right: 12, endingOn: .right)
            builder.diaper(at(7, 10), .wet, pee: .medium)
            builder.sleep(at(8, 15), at(9, 30))
            if dayOffset == 0 {
                // Today: a feed that is still going on the left side.
                builder.runningNursing(since: at(9, 33))
                continue
            }
            builder.diaper(at(9, 35), .mixed, pee: .medium, color: .yellow, consistency: .seedy)
            builder.bottle(at(10, 5), ml: 120, content: .breastMilk)
            builder.pumping(at(10, 40), minutes: 15, left: 60, right: 75)
            builder.activity(at(11, 0), minutes: 10, type: .tummyTime)
            builder.sleep(at(11, 45), at(13, 20))
            builder.nursing(at(13, 30), left: 10, right: 9, endingOn: .right)
            builder.diaper(at(14, 0), .wet, pee: .large)
            builder.sleep(at(15, 30), at(16, 15))
            builder.bottle(at(16, 40), ml: 150, content: .formula)
            builder.diaper(at(17, 20), .dirty, color: .yellow, consistency: .mushy)
            builder.activity(at(18, 10), minutes: 15, type: .bath)
            builder.nursing(at(18, 50), left: 12, right: 10, endingOn: .left)
            builder.diaper(at(19, 15), .wet, pee: .medium)
            if dayOffset == 2 {
                builder.note(at(16, 20), note)
            }
        }

        // Monthly check-ups.
        let growth: [(days: Int, kg: Double, cm: Double, head: Double)] = [
            (0, 3.3, 49.5, 34.2), (30, 4.3, 53.8, 36.6), (61, 5.3, 57.4, 38.4), (91, 6.0, 60.1, 39.6),
        ]
        for point in growth {
            builder.growth(birth.addingTimeInterval(TimeInterval(point.days) * 86_400 + 6 * 3600), kg: point.kg, cm: point.cm, head: point.head)
        }

        return Dataset(baby: baby, events: builder.events.sorted { $0.startDate < $1.startDate })
    }

    /// Stable IDs so snapshot tests and screenshots never depend on random UUIDs.
    static func uuid(_ a: Int, _ b: Int) -> UUID {
        UUID(uuidString: String(format: "DE000000-0000-4000-8000-%06X%06X", a, b))!
    }

    private struct Builder {
        let babyID: UUID
        let now: Date
        var events: [EventRecord] = []

        private mutating func add(_ record: EventRecord) {
            // Only the past is logged.
            guard record.startDate <= now else { return }
            var r = record
            r.id = DemoData.uuid(1, events.count + 1)
            if let end = r.endDate, end > now { r.endDate = nil }
            if r.endDate == nil, r.kind.supportsTimer, r.kind != .nursing || r.activeSide == nil {
                // A timed entry that would still be running: drop it rather than leave a stray timer.
                return
            }
            r.createdAt = r.endDate ?? r.startDate
            r.updatedAt = r.createdAt
            events.append(r)
        }

        mutating func sleep(_ start: Date, _ end: Date) {
            add(EventRecord(babyID: babyID, kind: .sleep, startDate: start, endDate: end, sleepLocation: .crib))
        }

        mutating func nursing(_ start: Date, left: Int, right: Int, endingOn last: BreastSide) {
            let total = TimeInterval((left + right) * 60)
            add(
                EventRecord(babyID: babyID, kind: .nursing, startDate: start, endDate: start.addingTimeInterval(total),
                            leftDuration: TimeInterval(left * 60), rightDuration: TimeInterval(right * 60), lastSide: last)
            )
        }

        mutating func runningNursing(since start: Date) {
            add(
                EventRecord(babyID: babyID, kind: .nursing, startDate: start,
                            activeSide: .left, activeSideStartedAt: start, lastSide: .left)
            )
        }

        mutating func bottle(_ date: Date, ml: Double, content: BottleContent) {
            // Bottles can be timed, and an untimed one would count as still running.
            add(EventRecord(babyID: babyID, kind: .bottle, startDate: date, endDate: date.addingTimeInterval(12 * 60),
                            amountML: ml, bottleContent: content))
        }

        mutating func pumping(_ start: Date, minutes: Int, left: Double, right: Double) {
            add(
                EventRecord(babyID: babyID, kind: .pumping, startDate: start, endDate: start.addingTimeInterval(TimeInterval(minutes * 60)),
                            leftAmountML: left, rightAmountML: right)
            )
        }

        mutating func diaper(_ date: Date, _ type: DiaperType, pee: PeeAmount? = nil, color: PoopColor? = nil, consistency: PoopConsistency? = nil) {
            add(
                EventRecord(babyID: babyID, kind: .diaper, startDate: date, diaperType: type, peeAmount: pee,
                            poopColor: color, poopConsistency: consistency)
            )
        }

        mutating func activity(_ start: Date, minutes: Int, type: ActivityType) {
            add(
                EventRecord(babyID: babyID, kind: .activity, startDate: start,
                            endDate: start.addingTimeInterval(TimeInterval(minutes * 60)), activityType: type)
            )
        }

        mutating func growth(_ date: Date, kg: Double, cm: Double, head: Double) {
            add(EventRecord(babyID: babyID, kind: .growth, startDate: date, weightKg: kg, heightCm: cm, headCm: head))
        }

        mutating func note(_ date: Date, _ text: String) {
            add(EventRecord(babyID: babyID, kind: .note, startDate: date, note: text))
        }
    }
}
