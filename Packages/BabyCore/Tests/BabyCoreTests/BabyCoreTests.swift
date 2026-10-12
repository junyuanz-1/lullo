import XCTest
@testable import BabyCore

final class NursingTimerTests: XCTestCase {
    let baby = UUID()
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testSwitchingSidesAccumulatesTime() {
        var e = EventRecord(babyID: baby, kind: .nursing, startDate: t0)
        e.startNursing(.left, at: t0)
        e.switchNursingSide(at: t0.addingTimeInterval(300))
        XCTAssertEqual(e.activeSide, .right)
        XCTAssertEqual(e.leftDuration, 300)
        XCTAssertEqual(e.nursingElapsed(.right, at: t0.addingTimeInterval(420)), 120)
        e.finishNursing(at: t0.addingTimeInterval(600))
        XCTAssertEqual(e.rightDuration, 300)
        XCTAssertEqual(e.nursingTotal(), 600)
        XCTAssertEqual(e.lastSide, .right)
        XCTAssertFalse(e.isOngoing)
    }

    func testPauseStopsTheClock() {
        var e = EventRecord(babyID: baby, kind: .nursing, startDate: t0)
        e.startNursing(.right, at: t0)
        e.pauseNursing(at: t0.addingTimeInterval(60))
        XCTAssertTrue(e.isNursingPaused)
        XCTAssertEqual(e.nursingTotal(at: t0.addingTimeInterval(1000)), 60)
        e.startNursing(.right, at: t0.addingTimeInterval(1000))
        XCTAssertEqual(e.nursingTotal(at: t0.addingTimeInterval(1030)), 90)
    }

    func testSuggestedSideIsOppositeOfLast() {
        var e = EventRecord(babyID: baby, kind: .nursing, startDate: t0)
        e.startNursing(.left, at: t0)
        e.finishNursing(at: t0.addingTimeInterval(10))
        XCTAssertEqual(EventRecord.suggestedNextSide(after: e), .right)
        XCTAssertEqual(EventRecord.suggestedNextSide(after: nil), .left)
    }
}

final class StatisticsTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let baby = UUID()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testSleepAcrossMidnightIsSplit() {
        let night = EventRecord(babyID: baby, kind: .sleep, startDate: date(1, 20), endDate: date(2, 6))
        let nap = EventRecord(babyID: baby, kind: .sleep, startDate: date(2, 10), endDate: date(2, 11, 30))
        let days = Statistics.dailySummaries(events: [night, nap], from: date(1, 0), to: date(2, 0), calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].totalSleep, 4 * 3600)
        XCTAssertEqual(days[0].nightSleep, 4 * 3600)
        XCTAssertEqual(days[1].totalSleep, 6 * 3600 + 5400)
        XCTAssertEqual(days[1].napSleep, 5400)
        XCTAssertEqual(days[1].napCount, 1)
        XCTAssertEqual(days[0].napCount, 0)
    }

    func testFeedsAndDiapers() {
        let events = [
            EventRecord(babyID: baby, kind: .bottle, startDate: date(3, 8), amountML: 120),
            EventRecord(babyID: baby, kind: .bottle, startDate: date(3, 11), amountML: 90),
            EventRecord(babyID: baby, kind: .nursing, startDate: date(3, 14), endDate: date(3, 14, 20), leftDuration: 600, rightDuration: 600),
            EventRecord(babyID: baby, kind: .diaper, startDate: date(3, 9), diaperType: .mixed),
            EventRecord(babyID: baby, kind: .diaper, startDate: date(3, 12), diaperType: .wet),
        ]
        let day = Statistics.dailySummaries(events: events, from: date(3, 0), to: date(3, 0), calendar: calendar)[0]
        XCTAssertEqual(day.feedCount, 3)
        XCTAssertEqual(day.bottleVolumeML, 210)
        XCTAssertEqual(day.nursingDuration, 1200)
        XCTAssertEqual(day.wetDiapers, 2)
        XCTAssertEqual(day.dirtyDiapers, 1)
        XCTAssertEqual(day.diaperCount, 2)
    }

    func testScheduleBlocksAreClippedToDay() {
        let night = EventRecord(babyID: baby, kind: .sleep, startDate: date(1, 22), endDate: date(2, 2))
        let rows = Statistics.schedules(events: [night], from: date(1, 0), to: date(2, 0), calendar: calendar)
        XCTAssertEqual(rows[0].blocks.first?.start, 22 * 3600)
        XCTAssertEqual(rows[0].blocks.first?.end, 24 * 3600)
        XCTAssertEqual(rows[1].blocks.first?.start, 0)
        XCTAssertEqual(rows[1].blocks.first?.end, 2 * 3600)
    }

    func testAverageIgnoresEmptyDays() {
        var a = DailySummary(day: date(1, 0)); a.feedCount = 8; a.totalSleep = 3600
        var b = DailySummary(day: date(2, 0)); b.feedCount = 6; b.totalSleep = 7200
        let c = DailySummary(day: date(3, 0))
        let avg = Statistics.average([a, b, c])
        XCTAssertEqual(avg?.feedCount, 7)
        XCTAssertEqual(avg?.totalSleep, 5400)
    }
}

final class GrowthTests: XCTestCase {
    func testMedianIsFiftiethPercentile() throws {
        let p = try XCTUnwrap(GrowthStandards.percentile(of: 7.934, metric: .weight, sex: .male, ageInMonths: 6))
        XCTAssertEqual(p, 50, accuracy: 0.01)
    }

    func testCurveMatchesPublishedPercentiles() throws {
        // WHO boys weight-for-age, month 6: 5th = 6.611702, 95th = 9.481939
        let p5 = GrowthStandards.curve(for: .weight, sex: .male, percentile: 5).first { $0.month == 6 }
        let p95 = GrowthStandards.curve(for: .weight, sex: .male, percentile: 95).first { $0.month == 6 }
        XCTAssertEqual(try XCTUnwrap(p5).value, 6.611702, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(p95).value, 9.481939, accuracy: 0.001)
        // WHO girls length-for-age, month 6: 25th = 64.20243
        let p25 = GrowthStandards.curve(for: .length, sex: .female, percentile: 25).first { $0.month == 6 }
        XCTAssertEqual(try XCTUnwrap(p25).value, 64.20243, accuracy: 0.001)
    }

    func testTablesCoverBirthToTwoYears() {
        for metric in GrowthMetric.allCases {
            for sex in [Sex.male, .female] {
                XCTAssertEqual(GrowthStandards.table(for: metric, sex: sex)?.count, 25)
            }
            XCTAssertNil(GrowthStandards.table(for: metric, sex: .unspecified))
        }
        XCTAssertNil(GrowthStandards.lms(for: .weight, sex: .male, ageInMonths: 30))
    }

    func testInverseNormal() {
        XCTAssertEqual(Statistics.inverseNormalCDF(0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(Statistics.inverseNormalCDF(0.975), 1.959964, accuracy: 1e-5)
        XCTAssertEqual(Statistics.normalCDF(1.959964), 0.975, accuracy: 1e-5)
    }
}

final class NapPredictorTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let baby = UUID()

    func testPredictionUsesAgeWakeWindow() throws {
        let birth = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        // ~4.5 months old -> 90–135 min wake window
        let wake = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 7))!
        let night = EventRecord(babyID: baby, kind: .sleep, startDate: wake.addingTimeInterval(-11 * 3600), endDate: wake)
        let prediction = try XCTUnwrap(NapPredictor.predict(birthDate: birth, sleeps: [night], now: wake.addingTimeInterval(600), calendar: calendar))
        XCTAssertEqual(prediction.earliest, wake.addingTimeInterval(90 * 60))
        XCTAssertFalse(prediction.isBedtime)
        XCTAssertFalse(prediction.isPersonalized)
        XCTAssertGreaterThan(prediction.latest, prediction.earliest)
    }

    func testNoPredictionWhileAsleep() {
        let now = Date()
        let sleeping = EventRecord(babyID: baby, kind: .sleep, startDate: now.addingTimeInterval(-600))
        XCTAssertNil(NapPredictor.predict(birthDate: now.addingTimeInterval(-90 * 86_400), sleeps: [sleeping], now: now))
    }

    func testWakeWindowsGrowWithAge() {
        XCTAssertLessThan(NapPredictor.typicalWakeWindow(ageInMonths: 0.5).max, NapPredictor.typicalWakeWindow(ageInMonths: 8).min)
        XCTAssertEqual(NapPredictor.recommendedDailySleepHours(ageInMonths: 2), 14...17)
    }
}

final class BackupTests: XCTestCase {
    func testRoundTrip() throws {
        let baby = BabyRecord(name: "Mia", birthDate: Date(timeIntervalSince1970: 1_700_000_000), sex: .female, photoData: Data([1, 2, 3]))
        let event = EventRecord(babyID: baby.id, kind: .bottle, startDate: Date(timeIntervalSince1970: 1_700_100_000.123), amountML: 120, bottleContent: .formula)
        let file = BackupFile(babies: [baby], events: [event])
        let decoded = try BackupCodec.decode(BackupCodec.encode(file))
        XCTAssertEqual(decoded.babies.first?.photoData, Data([1, 2, 3]))
        XCTAssertEqual(decoded.events.first?.amountML, 120)
        XCTAssertEqual(decoded.events.first!.startDate.timeIntervalSince1970, 1_700_100_000.123, accuracy: 0.001)
    }

    func testDecodingToleratesMissingAndUnknownFields() throws {
        let json = """
        {"formatVersion":1,"exportedAt":"2026-01-01T00:00:00Z","babies":[],
         "events":[{"id":"\(UUID().uuidString)","babyID":"\(UUID().uuidString)","kind":"diaper",
                    "startDate":"2026-01-01T08:00:00Z","diaperType":"wet","poopColor":"sparkly","future":1}]}
        """
        let file = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(file.events.first?.diaperType, .wet)
        XCTAssertNil(file.events.first?.poopColor)
        XCTAssertEqual(file.events.first?.hasRash, false)
    }

    func testRejectsNewerFormat() {
        let json = #"{"formatVersion":99,"exportedAt":"2026-01-01T00:00:00Z","babies":[],"events":[]}"#
        XCTAssertThrowsError(try BackupCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion(99))
        }
    }

    func testMergePlanKeepsNewest() {
        let babyID = UUID()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let a = EventRecord(babyID: babyID, kind: .diaper, startDate: t, updatedAt: t.addingTimeInterval(10))
        let b = EventRecord(babyID: babyID, kind: .diaper, startDate: t, updatedAt: t)
        let c = EventRecord(babyID: babyID, kind: .diaper, startDate: t, updatedAt: t)
        let plan = BackupMerge.plan(events: [a, b, c, c], existingUpdatedAt: [a.id: t, b.id: t.addingTimeInterval(5)])
        XCTAssertEqual(plan.updates.map(\.id), [a.id])
        XCTAssertEqual(plan.inserts.map(\.id), [c.id])
        XCTAssertEqual(plan.skipped, 1)
    }

    func testCSVEscaping() {
        let baby = BabyRecord(name: "Leo", birthDate: Date())
        let event = EventRecord(babyID: baby.id, kind: .note, startDate: Date(timeIntervalSince1970: 0), note: "said \"hi\", smiled")
        let csv = CSVExporter.csv(events: [event], babies: [baby], timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0].split(separator: ",").count, CSVExporter.header.count)
        XCTAssertTrue(lines[1].contains("\"said \"\"hi\"\", smiled\""))
        XCTAssertTrue(lines[1].contains("1970-01-01 00:00:00"))
    }
}

final class DiaperTests: XCTestCase {
    func testPeeAmountRoundTripsAndExports() throws {
        let baby = BabyRecord(name: "Leo", birthDate: Date())
        let wet = EventRecord(babyID: baby.id, kind: .diaper, startDate: Date(timeIntervalSince1970: 0), diaperType: .mixed, peeAmount: .large)
        let decoded = try BackupCodec.decode(BackupCodec.encode(BackupFile(babies: [baby], events: [wet])))
        XCTAssertEqual(decoded.events.first?.peeAmount, .large)

        let csv = CSVExporter.csv(events: [wet], babies: [baby], timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.components(separatedBy: "\r\n")
        let column = try XCTUnwrap(CSVExporter.header.firstIndex(of: "pee_amount"))
        XCTAssertEqual(lines[1].components(separatedBy: ",")[column], "large")
    }

    func testPeeAmountIsOmittedForDirtyOnly() throws {
        let baby = BabyRecord(name: "Leo", birthDate: Date())
        let dirty = EventRecord(babyID: baby.id, kind: .diaper, startDate: Date(timeIntervalSince1970: 0), diaperType: .dirty, peeAmount: .small)
        let csv = CSVExporter.csv(events: [dirty], babies: [baby], timeZone: TimeZone(identifier: "UTC")!)
        let column = try XCTUnwrap(CSVExporter.header.firstIndex(of: "pee_amount"))
        XCTAssertEqual(csv.components(separatedBy: "\r\n")[1].components(separatedBy: ",")[column], "")
    }
}

final class RebaseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testUntouchedFieldsFollowTheStore() {
        // Editor opened on a running sleep; the timer is stopped from the Lock Screen.
        let base = EventRecord(babyID: UUID(), kind: .sleep, startDate: start)
        var latest = base
        latest.endDate = start.addingTimeInterval(3600)
        let merged = base.rebased(onto: latest, from: base)
        XCTAssertEqual(merged.endDate, latest.endDate)
        XCTAssertFalse(merged.isOngoing)
    }

    func testLocalEditsWin() {
        let base = EventRecord(babyID: UUID(), kind: .sleep, startDate: start)
        var draft = base
        draft.note = "fussy"
        draft.sleepLocation = .crib
        var latest = base
        latest.endDate = start.addingTimeInterval(1800)
        latest.sleepLocation = .stroller
        let merged = draft.rebased(onto: latest, from: base)
        XCTAssertEqual(merged.note, "fussy")
        XCTAssertEqual(merged.sleepLocation, .crib)
        XCTAssertEqual(merged.endDate, latest.endDate)
    }
}

final class RollbackTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    func testRollbackRestoresEditsDeletionsAndRemovesNewEntries() {
        let baby = BabyRecord(name: "Mia", birthDate: t)
        let other = BabyRecord(name: "Leo", birthDate: t)
        let unchanged = EventRecord(babyID: baby.id, kind: .diaper, startDate: t, diaperType: .wet)
        let edited = EventRecord(babyID: baby.id, kind: .bottle, startDate: t, amountML: 120)
        let deleted = EventRecord(babyID: baby.id, kind: .note, startDate: t, note: "hi")
        let backup = BackupFile(babies: [baby], events: [unchanged, edited, deleted])

        var editedNow = edited
        editedNow.amountML = 999
        editedNow.updatedAt = t.addingTimeInterval(60)
        let addedLater = EventRecord(babyID: baby.id, kind: .diaper, startDate: t.addingTimeInterval(100))
        let otherBabyEvent = EventRecord(babyID: other.id, kind: .diaper, startDate: t)

        let now = t.addingTimeInterval(3600)
        let plan = BackupRollback.plan(
            backup: backup,
            currentBabies: [baby, other],
            currentEvents: [unchanged, editedNow, addedLater, otherBabyEvent],
            babyIDs: [baby.id],
            now: now
        )
        XCTAssertTrue(plan.upsertBabies.isEmpty)
        XCTAssertEqual(Set(plan.upsertEvents.map(\.id)), [edited.id, deleted.id])
        XCTAssertEqual(plan.upsertEvents.first { $0.id == edited.id }?.amountML, 120)
        XCTAssertTrue(plan.upsertEvents.allSatisfy { $0.updatedAt == now })
        XCTAssertEqual(plan.deleteEventIDs, [addedLater.id])
        XCTAssertEqual(plan.unchangedEvents, 1)
    }

    func testRollbackRecreatesDeletedBaby() {
        let baby = BabyRecord(name: "Mia", birthDate: t)
        let plan = BackupRollback.plan(backup: BackupFile(babies: [baby], events: []), currentBabies: [], currentEvents: [], babyIDs: [baby.id])
        XCTAssertEqual(plan.upsertBabies.map(\.id), [baby.id])
    }

    func testRoundTripThroughFileIsUnchanged() throws {
        let baby = BabyRecord(name: "Mia", birthDate: Date(timeIntervalSince1970: 1_700_000_000.123456))
        let event = EventRecord(babyID: baby.id, kind: .sleep, startDate: Date(timeIntervalSince1970: 1_700_000_100.987654), endDate: Date(timeIntervalSince1970: 1_700_003_000.5))
        let file = try BackupCodec.decode(BackupCodec.encode(BackupFile(babies: [baby], events: [event])))
        let plan = BackupRollback.plan(backup: file, currentBabies: [baby], currentEvents: [event], babyIDs: [baby.id])
        XCTAssertEqual(plan.changeCount, 0)
    }

    func testDailyScheduleAndRetention() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC
        XCTAssertTrue(AutoBackupPolicy.isDue(lastBackup: nil, now: morning, calendar: calendar))
        XCTAssertFalse(AutoBackupPolicy.isDue(lastBackup: morning.addingTimeInterval(-3600), now: morning, calendar: calendar))
        XCTAssertTrue(AutoBackupPolicy.isDue(lastBackup: morning, now: morning.addingTimeInterval(3 * 3600), calendar: calendar))

        let dates = (0..<12).map { morning.addingTimeInterval(Double($0) * 86_400) }
        let pruned = AutoBackupPolicy.toPrune(dates.shuffled(), date: { $0 })
        XCTAssertEqual(pruned.sorted(), Array(dates.prefix(2)))
    }
}

final class TimerAlarmTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    func testTimerAlarmCountsFromStart() {
        let nap = EventRecord(babyID: UUID(), kind: .sleep, startDate: t)
        XCTAssertEqual(TimerAlarm.fireDate(for: nap, after: 45 * 60, now: t.addingTimeInterval(60)), t.addingTimeInterval(45 * 60))
        XCTAssertNil(TimerAlarm.fireDate(for: nap, after: 45 * 60, now: t.addingTimeInterval(46 * 60)), "Already passed")
        var stopped = nap
        stopped.endDate = t.addingTimeInterval(600)
        XCTAssertNil(TimerAlarm.fireDate(for: stopped, after: 45 * 60, now: t))
    }

    func testNursingAlarmIsPerSide() {
        var feed = EventRecord(babyID: UUID(), kind: .nursing, startDate: t)
        feed.startNursing(.left, at: t)
        XCTAssertEqual(TimerAlarm.fireDate(for: feed, after: 600, now: t), t.addingTimeInterval(600))

        // Switch after 4 minutes: the right side gets its own 10 minutes.
        feed.startNursing(.right, at: t.addingTimeInterval(240))
        XCTAssertEqual(TimerAlarm.fireDate(for: feed, after: 600, now: t.addingTimeInterval(240)), t.addingTimeInterval(840))

        // Back to the left side, which already has 4 minutes banked.
        feed.startNursing(.left, at: t.addingTimeInterval(900))
        XCTAssertEqual(TimerAlarm.fireDate(for: feed, after: 600, now: t.addingTimeInterval(900)), t.addingTimeInterval(900 + 360))

        feed.pauseNursing(at: t.addingTimeInterval(1000))
        XCTAssertNil(TimerAlarm.fireDate(for: feed, after: 600, now: t.addingTimeInterval(1000)), "Paused")
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotSummarisesLatestState() throws {
        let now = Date()
        let baby = BabyRecord(name: "Mia", birthDate: now.addingTimeInterval(-60 * 86_400))
        var nursing = EventRecord(babyID: baby.id, kind: .nursing, startDate: now.addingTimeInterval(-300))
        nursing.startNursing(.left, at: now.addingTimeInterval(-300))
        let events = [
            EventRecord(babyID: baby.id, kind: .sleep, startDate: now.addingTimeInterval(-7200), endDate: now.addingTimeInterval(-3600)),
            EventRecord(babyID: baby.id, kind: .diaper, startDate: now.addingTimeInterval(-1000), diaperType: .dirty),
            nursing,
            EventRecord(babyID: UUID(), kind: .diaper, startDate: now, diaperType: .wet),
        ]
        let snap = WidgetSnapshotBuilder.make(baby: baby, events: events, now: now)
        XCTAssertEqual(snap.lastDiaper?.type, .dirty)
        XCTAssertEqual(snap.lastFeed?.kind, .nursing)
        XCTAssertEqual(snap.runningNursing?.activeSide, .left)
        XCTAssertEqual(snap.awakeSince, now.addingTimeInterval(-3600))
        XCTAssertNotNil(snap.nextNap)

        let full = WidgetSnapshot(selectedBabyID: baby.id, babies: [snap], unitSystem: .imperial)
        let decoded = try WidgetSnapshotBuilder.decode(WidgetSnapshotBuilder.encode(full))
        XCTAssertEqual(decoded.baby(nil)?.name, "Mia")
    }
}

final class UnitTests: XCTestCase {
    func testConversions() {
        XCTAssertEqual(UnitConversion.ounces(fromML: 29.5735), 1, accuracy: 1e-9)
        XCTAssertEqual(UnitConversion.fahrenheit(fromCelsius: 37), 98.6, accuracy: 1e-9)
        let lbOz = UnitConversion.poundsAndOunces(fromKg: 3.5)
        XCTAssertEqual(lbOz.pounds, 7)
        XCTAssertEqual(lbOz.ounces, 11.46, accuracy: 0.01)
    }
}
