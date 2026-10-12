import BabyCore
import XCTest
@testable import Tinytide

@MainActor
final class AutoBackupTests: XCTestCase {
    private var store: TrackerStore!
    private var backups: AutoBackup!
    private var directory: URL!

    override func setUp() async throws {
        AppSettings.selectedBabyID = nil
        store = TrackerStore(persistence: PersistenceController(inMemory: true))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        backups = AutoBackup(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testOneDailyBackupPerDay() throws {
        store.addBaby(BabyRecord(name: "Mia", birthDate: Date()))
        let now = Date()
        backups.backUpIfDue(store: store, now: now)
        backups.backUpIfDue(store: store, now: now.addingTimeInterval(60))
        XCTAssertEqual(backups.entries.count, 1)
        XCTAssertEqual(backups.entries.first?.reason, .daily)
    }

    func testKeepsTenNewest() throws {
        store.addBaby(BabyRecord(name: "Mia", birthDate: Date()))
        let start = Date()
        for day in 0..<12 {
            try backups.backUp(store: store, reason: .manual, now: start.addingTimeInterval(Double(day) * 86_400))
        }
        XCTAssertEqual(backups.entries.count, AutoBackupPolicy.keepCount)
        XCTAssertEqual(Int(backups.entries.last!.date.timeIntervalSince1970), Int(start.addingTimeInterval(2 * 86_400).timeIntervalSince1970))
    }

    func testRestoreRollsBackAndCanBeUndone() throws {
        let baby = store.addBaby(BabyRecord(name: "Mia", birthDate: Date()))
        store.logDiaper(.wet, for: baby)
        let snapshot = try backups.backUp(store: store, reason: .manual, now: Date().addingTimeInterval(-60))

        store.logDiaper(.dirty, for: baby)
        if let first = store.events(for: baby).first(where: { $0.record.diaperType == .wet }) {
            store.delete(first)
        }
        XCTAssertEqual(store.events(for: baby).map(\.record.diaperType), [.dirty])

        _ = try backups.restore(snapshot, store: store)
        XCTAssertEqual(store.events(for: baby).map(\.record.diaperType), [.wet])

        let undo = try XCTUnwrap(backups.entries.first { $0.reason == .beforeRestore })
        _ = try backups.restore(undo, store: store)
        XCTAssertEqual(store.events(for: baby).map(\.record.diaperType), [.dirty])
    }
}
