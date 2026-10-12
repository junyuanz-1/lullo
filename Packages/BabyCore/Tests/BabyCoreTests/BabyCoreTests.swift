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

    func testSleepMostlyInNightWindowIsNightSleep() {
        // Starts at 18:50, before the 19:00 night window, but is mostly inside it.
        let night = EventRecord(babyID: baby, kind: .sleep, startDate: date(1, 18, 50), endDate: date(2, 6, 30))
        let days = Statistics.dailySummaries(events: [night], from: date(1, 0), to: date(2, 0), calendar: calendar)
        XCTAssertEqual(days[0].napCount, 0)
        XCTAssertEqual(days[0].nightSleep, 5 * 3600 + 600)
        XCTAssertEqual(days[1].nightSleep, 6 * 3600 + 1800)
        XCTAssertEqual(days[0].napSleep + days[1].napSleep, 0)
    }

    func testDaysAreKeyedAtStartOfDayAcrossSkippedMidnight() throws {
        // Chile starts DST on 2026-09-06: 00:00 jumps to 01:00, so that day starts at 01:00.
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        func local(_ day: Int, _ hour: Int) -> Date {
            santiago.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let diapers = (5...8).map { EventRecord(babyID: baby, kind: .diaper, startDate: local($0, 12), diaperType: .wet) }
        let sleep = EventRecord(babyID: baby, kind: .sleep, startDate: local(6, 20), endDate: local(7, 6))

        let days = Statistics.dailySummaries(
            events: diapers + [sleep], from: local(5, 12), to: local(8, 12), now: local(9, 0), calendar: santiago
        )
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(days.map(\.day), (5...8).map { santiago.startOfDay(for: local($0, 12)) })
        XCTAssertEqual(santiago.component(.hour, from: days[1].day), 1)
        XCTAssertEqual(days.map(\.diaperCount), [1, 1, 1, 1])
        // 20:00 to midnight, then midnight to 06:00 (both at UTC-3).
        XCTAssertEqual(days[1].totalSleep, 4 * 3600)
        XCTAssertEqual(days[2].totalSleep, 6 * 3600)
        XCTAssertEqual(days[1].nightSleep, 4 * 3600)
        XCTAssertEqual(days[2].nightSleep, 6 * 3600)

        let rows = Statistics.schedules(events: [sleep], from: local(5, 12), to: local(8, 12), now: local(9, 0), calendar: santiago)
        XCTAssertEqual(rows.map(\.dayLength), [24, 23, 24, 24].map { Double($0) * 3600 })
        // 20:00 is 19 h after the 01:00 start of that day.
        XCTAssertEqual(rows[1].blocks.first?.start, 19 * 3600)
        XCTAssertEqual(rows[1].blocks.first?.end, 23 * 3600)
        XCTAssertEqual(rows[2].blocks.first?.start, 0)
        XCTAssertEqual(rows[2].blocks.first?.end, 6 * 3600)
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

final class SleepClassifierTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testMostOfTheSleepDecides() {
        let c = SleepClassifier(nightStartHour: 19, nightEndHour: 6)
        XCTAssertTrue(c.isNight(start: date(1, 18, 50), end: date(2, 6, 30), calendar: calendar))
        XCTAssertFalse(c.isNight(date(1, 18, 50), calendar: calendar), "The start hour alone says nap")
        XCTAssertFalse(c.isNight(start: date(2, 13), end: date(2, 15), calendar: calendar))
        // 05:00–07:30: one of two and a half hours is before 06:00, so a nap.
        XCTAssertEqual(c.nightOverlap(start: date(2, 5), end: date(2, 7, 30), calendar: calendar), 3600)
        XCTAssertFalse(c.isNight(start: date(2, 5), end: date(2, 7, 30), calendar: calendar))
        // 04:00–07:00: two of three hours, so night.
        XCTAssertTrue(c.isNight(start: date(2, 4), end: date(2, 7), calendar: calendar))
        // No duration: the start hour decides.
        XCTAssertTrue(c.isNight(start: date(1, 20), end: date(1, 20), calendar: calendar))
    }

    func testRunningSleepCountsUpToNow() {
        let c = SleepClassifier()
        let sleep = EventRecord(babyID: UUID(), kind: .sleep, startDate: date(1, 17))
        XCTAssertFalse(c.isNight(sleep, now: date(1, 20), calendar: calendar), "1 of 3 h")
        XCTAssertTrue(c.isNight(sleep, now: date(2, 1), calendar: calendar), "6 of 8 h")
    }

    func testNonWrappingWindow() {
        let c = SleepClassifier(nightStartHour: 0, nightEndHour: 6)
        XCTAssertTrue(c.isNight(date(2, 3), calendar: calendar))
        XCTAssertFalse(c.isNight(date(2, 12), calendar: calendar))
        XCTAssertFalse(c.isNight(date(1, 23), calendar: calendar))
        XCTAssertTrue(c.isNight(start: date(1, 23), end: date(2, 5), calendar: calendar), "5 of 6 h")
        XCTAssertFalse(c.isNight(start: date(2, 4), end: date(2, 9), calendar: calendar), "2 of 5 h")
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

    func testUnknownEventKindAndSexDoNotFailTheFile() throws {
        let babyID = UUID()
        let json = """
        {"formatVersion":1,"exportedAt":"2026-01-01T00:00:00Z",
         "babies":[{"id":"\(babyID.uuidString)","name":"Mia","birthDate":"2025-10-01T00:00:00Z","sex":"other",
                    "createdAt":"2025-10-01T00:00:00Z","updatedAt":"2025-10-01T00:00:00Z"}],
         "events":[
           {"id":"\(UUID().uuidString)","babyID":"\(babyID.uuidString)","kind":"diaper","startDate":"2026-01-01T08:00:00Z","diaperType":"wet"},
           {"id":"\(UUID().uuidString)","babyID":"\(babyID.uuidString)","kind":"teething","startDate":"2026-01-01T09:00:00Z"},
           {"id":"\(UUID().uuidString)","babyID":"\(babyID.uuidString)","kind":"bottle","startDate":"2026-01-01T10:00:00Z","amountML":90}]}
        """
        let file = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(file.babies.map(\.id), [babyID])
        XCTAssertEqual(file.babies.first?.sex, .unspecified)
        XCTAssertEqual(file.events.map(\.kind), [.diaper, .bottle])
    }

    func testNewerFormatIsReportedEvenIfItsPayloadDiffers() {
        let json = #"{"formatVersion":2,"exportedAt":1767225600,"profiles":{}}"#
        XCTAssertThrowsError(try BackupCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("not a backup".utf8))) { error in
            guard case .corrupt? = error as? BackupError else { return XCTFail("Expected corrupt, got \(error)") }
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

    func testCSVNeutralizesFormulasInTextOnly() throws {
        let baby = BabyRecord(name: "@Leo", birthDate: Date())
        let t = Date(timeIntervalSince1970: 0)
        let events = [
            EventRecord(babyID: baby.id, kind: .note, startDate: t, note: "=1+1"),
            EventRecord(babyID: baby.id, kind: .note, startDate: t.addingTimeInterval(60), note: "-fussy"),
            EventRecord(babyID: baby.id, kind: .temperature, startDate: t.addingTimeInterval(120), note: "fussy", temperatureC: -0.5),
            EventRecord(babyID: baby.id, kind: .note, startDate: t.addingTimeInterval(180), note: "=SUM(A1,B1)"),
        ]
        let lines = CSVExporter.csv(events: events, babies: [baby], timeZone: TimeZone(identifier: "UTC")!)
            .components(separatedBy: "\r\n")
        let note = try XCTUnwrap(CSVExporter.header.firstIndex(of: "note"))
        let name = try XCTUnwrap(CSVExporter.header.firstIndex(of: "baby"))
        let temperature = try XCTUnwrap(CSVExporter.header.firstIndex(of: "temperature_c"))
        XCTAssertEqual(lines[1].components(separatedBy: ",")[note], "'=1+1")
        XCTAssertEqual(lines[1].components(separatedBy: ",")[name], "'@Leo")
        XCTAssertEqual(lines[2].components(separatedBy: ",")[note], "'-fussy")
        XCTAssertEqual(lines[3].components(separatedBy: ",")[note], "fussy")
        XCTAssertEqual(lines[3].components(separatedBy: ",")[temperature], "-0.5")
        XCTAssertTrue(lines[4].contains("\"'=SUM(A1,B1)\""))
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
        let backup = BackupFile(exportedAt: t.addingTimeInterval(50), babies: [baby], events: [unchanged, edited, deleted])

        var editedNow = edited
        editedNow.amountML = 999
        editedNow.updatedAt = t.addingTimeInterval(60)
        let addedLater = EventRecord(
            babyID: baby.id, kind: .diaper, startDate: t.addingTimeInterval(100),
            createdAt: t.addingTimeInterval(100), updatedAt: t.addingTimeInterval(100)
        )
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

    func testRollbackOnlyDeletesEntriesChangedAfterTheBackup() {
        let baby = BabyRecord(name: "Mia", birthDate: t)
        let backup = BackupFile(exportedAt: t.addingTimeInterval(3600), babies: [baby], events: [])
        // Logged on another device before the backup, synced after it: kept.
        let syncedLate = EventRecord(babyID: baby.id, kind: .diaper, startDate: t, createdAt: t, updatedAt: t)
        let addedAfter = EventRecord(
            babyID: baby.id, kind: .diaper, startDate: t.addingTimeInterval(7200),
            createdAt: t.addingTimeInterval(7200), updatedAt: t.addingTimeInterval(7200)
        )
        // Put back by a later restore: old createdAt but a new updatedAt, so undoing
        // that restore removes it.
        let restoredLater = EventRecord(
            babyID: baby.id, kind: .bottle, startDate: t,
            createdAt: t, updatedAt: t.addingTimeInterval(7200), amountML: 90
        )
        let plan = BackupRollback.plan(
            backup: backup,
            currentBabies: [baby],
            currentEvents: [syncedLate, addedAfter, restoredLater],
            babyIDs: [baby.id]
        )
        XCTAssertEqual(Set(plan.deleteEventIDs), [addedAfter.id, restoredLater.id])
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

final class DemoDataTests: XCTestCase {
    func testDemoWeekLooksLikeARealBaby() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 9, minute: 41))!
        let data = DemoData.make(now: now, calendar: calendar)

        XCTAssertTrue(data.events.allSatisfy { $0.startDate <= now && ($0.endDate ?? now) <= now })
        XCTAssertEqual(data.events.filter(\.isOngoing).map(\.kind), [.nursing], "One feed in progress")
        XCTAssertEqual(Set(data.events.map(\.id)).count, data.events.count)
        XCTAssertEqual(data.events.filter { $0.kind == .growth }.count, 4)
        XCTAssertEqual(data.baby.ageInDays(at: now, calendar: calendar), 98)

        // Yesterday should look like a typical day for a three-month-old.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let summary = try XCTUnwrap(Statistics.dailySummaries(
            events: data.events, from: yesterday, to: yesterday, now: now, calendar: calendar
        ).first)
        XCTAssertEqual(summary.totalSleep / 3600, 14.5, accuracy: 1.5)
        XCTAssertGreaterThanOrEqual(summary.feedCount, 6)
        XCTAssertGreaterThanOrEqual(summary.wetDiapers, 5)
        XCTAssertGreaterThanOrEqual(summary.fussyCount, 1)

        // Same input, same output.
        XCTAssertEqual(DemoData.make(now: now, calendar: calendar).events, data.events)
    }
}

final class FussyTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let baby = UUID()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testAMomentHasNoDurationAndIsNotATimer() {
        let moment = EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 17))
        XCTAssertFalse(moment.isOngoing)
        XCTAssertFalse(moment.hasTimeRange)
        XCTAssertEqual(moment.duration(at: date(3, 18)), 0)
        XCTAssertEqual(moment.effectiveEnd(at: date(3, 18)), moment.startDate)
    }

    func testAnEndTimeMakesASpell() {
        let spell = EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 17), endDate: date(3, 17, 40))
        XCTAssertTrue(spell.hasTimeRange)
        XCTAssertFalse(spell.isOngoing)
        XCTAssertEqual(spell.duration(at: date(3, 20)), 40 * 60)
        XCTAssertEqual(spell.effectiveEnd(at: date(3, 20)), date(3, 17, 40))
    }

    func testDailyCountAndMinutes() {
        let events = [
            EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 10)),
            EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 17), endDate: date(3, 17, 30)),
            EventRecord(babyID: baby, kind: .fussy, startDate: date(4, 18), endDate: date(4, 18, 10)),
        ]
        let days = Statistics.dailySummaries(events: events, from: date(3, 0), to: date(4, 0), now: date(5, 0), calendar: calendar)
        XCTAssertEqual(days.map(\.fussyCount), [2, 1])
        XCTAssertEqual(days.map(\.fussyDuration), [1800, 600])
    }

    func testScheduleShowsSpellsAsBlocksAndMomentsAsMarks() {
        let events = [
            EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 10)),
            EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 17), endDate: date(3, 17, 30)),
        ]
        let row = Statistics.schedules(events: events, from: date(3, 0), to: date(3, 0), now: date(4, 0), calendar: calendar)[0]
        XCTAssertEqual(row.marks, [.init(offset: 10.0 * 3600, kind: .fussy)])
        XCTAssertEqual(row.blocks, [.init(start: 17.0 * 3600, end: 17.5 * 3600, kind: .fussy)])
    }

    func testDetailsRoundTripThroughBackupAndCSV() throws {
        let mia = BabyRecord(name: "Mia", birthDate: date(1, 0))
        let spell = EventRecord(
            babyID: mia.id, kind: .fussy, startDate: date(3, 17), endDate: date(3, 17, 25),
            fussIntensity: .intense, fussCauses: [.gas, .tired], soothingMethods: [.holding, .whiteNoise]
        )
        let decoded = try XCTUnwrap(BackupCodec.decode(BackupCodec.encode(BackupFile(babies: [mia], events: [spell]))).events.first)
        XCTAssertEqual(decoded.kind, .fussy)
        XCTAssertEqual(decoded.endDate, spell.endDate)
        XCTAssertEqual(decoded.fussIntensity, .intense)
        XCTAssertEqual(decoded.fussCauses, [.gas, .tired])
        XCTAssertEqual(decoded.soothingMethods, [.holding, .whiteNoise])

        let lines = CSVExporter.csv(events: [spell], babies: [mia], timeZone: TimeZone(identifier: "UTC")!).components(separatedBy: "\r\n")
        let row = lines[1].components(separatedBy: ",")
        XCTAssertEqual(row.count, CSVExporter.header.count)
        XCTAssertEqual(row[try XCTUnwrap(CSVExporter.header.firstIndex(of: "type"))], "fussy")
        XCTAssertEqual(row[try XCTUnwrap(CSVExporter.header.firstIndex(of: "duration_min"))], "25.0")
        XCTAssertEqual(row[try XCTUnwrap(CSVExporter.header.firstIndex(of: "fuss_intensity"))], "intense")
        XCTAssertEqual(row[try XCTUnwrap(CSVExporter.header.firstIndex(of: "fuss_causes"))], "gas;tired")
        XCTAssertEqual(row[try XCTUnwrap(CSVExporter.header.firstIndex(of: "soothing"))], "holding;whiteNoise")

        let moment = EventRecord(babyID: mia.id, kind: .fussy, startDate: date(3, 9))
        let momentRow = CSVExporter.csv(events: [moment], babies: [mia]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
        XCTAssertEqual(momentRow[try XCTUnwrap(CSVExporter.header.firstIndex(of: "duration_min"))], "")
    }

    func testUnknownChoicesAreDroppedNotTheEntry() throws {
        let json = """
        {"formatVersion":1,"exportedAt":"2026-01-01T00:00:00Z","babies":[],
         "events":[{"id":"\(UUID().uuidString)","babyID":"\(UUID().uuidString)","kind":"fussy",
                    "startDate":"2026-01-01T08:00:00Z","fussIntensity":"volcanic",
                    "fussCauses":["moonPhase","hungry"],"soothingMethods":"rocking"}]}
        """
        let event = try XCTUnwrap(BackupCodec.decode(Data(json.utf8)).events.first)
        XCTAssertEqual(event.kind, .fussy)
        XCTAssertNil(event.fussIntensity)
        XCTAssertEqual(event.fussCauses, [.hungry])
        XCTAssertEqual(event.soothingMethods, [])
    }

    func testChoicesAreStoredAsOrderedText() {
        XCTAssertEqual(EventRecord.joinedRawValues([FussCause.tired, .hungry]), "hungry,tired")
        XCTAssertNil(EventRecord.joinedRawValues([SoothingMethod]()))
        let parsed: [SoothingMethod] = EventRecord.parseRawValues("rocking,dancing,pacifier")
        XCTAssertEqual(parsed, [.rocking, .pacifier])
        XCTAssertEqual(EventRecord.parseRawValues(nil) as [FussCause], [])
    }

    func testEditsToChoicesSurviveARebase() {
        let base = EventRecord(babyID: baby, kind: .fussy, startDate: date(3, 17))
        var draft = base
        draft.fussCauses = [.colic]
        var latest = base
        latest.note = "from the other phone"
        latest.soothingMethods = [.rocking]
        let merged = draft.rebased(onto: latest, from: base)
        XCTAssertEqual(merged.fussCauses, [.colic])
        XCTAssertEqual(merged.soothingMethods, [.rocking])
        XCTAssertEqual(merged.note, "from the other phone")
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

    func testPoundsAndOuncesSurviveBadInput() {
        for kg in [Double.nan, Double.infinity, -Double.infinity, -3] {
            let lbOz = UnitConversion.poundsAndOunces(fromKg: kg)
            XCTAssertEqual(lbOz.pounds, 0)
            XCTAssertEqual(lbOz.ounces, 0)
        }
        let huge = UnitConversion.poundsAndOunces(fromKg: 1e20)
        XCTAssertEqual(huge.pounds, 10_000)
        XCTAssertEqual(huge.ounces, 0)
    }
}
