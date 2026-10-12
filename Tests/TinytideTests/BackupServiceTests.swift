import BabyCore
import CoreData
import XCTest
@testable import Tinytide

@MainActor
final class BackupServiceTests: XCTestCase {
    override func setUp() async throws {
        AppSettings.selectedBabyID = nil
    }

    private func makeStore() -> TrackerStore {
        TrackerStore(persistence: PersistenceController(inMemory: true))
    }

    private func populate(_ store: TrackerStore) throws -> Baby {
        let baby = store.addBaby(BabyRecord(name: "Mia", birthDate: Date().addingTimeInterval(-60 * 86_400), sex: .female))
        let id = try XCTUnwrap(baby.id)
        store.save(EventRecord(babyID: id, kind: .bottle, startDate: Date().addingTimeInterval(-3600), amountML: 120, bottleContent: .formula))
        store.save(EventRecord(babyID: id, kind: .sleep, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-5400)))
        store.save(EventRecord(babyID: id, kind: .growth, startDate: Date(), weightKg: 5.2, heightCm: 58))
        return baby
    }

    func testExportThenImportIntoEmptyStore() throws {
        let source = makeStore()
        _ = try populate(source)
        let url = try BackupService.exportBackup(store: source)
        let file = try BackupService.readBackup(at: url)
        XCTAssertEqual(file.babies.count, 1)
        XCTAssertEqual(file.events.count, 3)

        let target = makeStore()
        let summary = BackupService.importBackup(file, into: target)
        XCTAssertEqual(summary.babiesAdded, 1)
        XCTAssertEqual(summary.eventsAdded, 3)

        let baby = try XCTUnwrap(target.babies().first)
        XCTAssertEqual(baby.name, "Mia")
        XCTAssertEqual(target.events(for: baby).count, 3)
        XCTAssertEqual(target.selectedBabyID, baby.id)
    }

    func testImportingTwiceDoesNotDuplicate() throws {
        let source = makeStore()
        _ = try populate(source)
        let file = BackupService.makeBackupFile(store: source)

        let target = makeStore()
        _ = BackupService.importBackup(file, into: target)
        let second = BackupService.importBackup(file, into: target)

        XCTAssertEqual(second.eventsAdded, 0)
        XCTAssertEqual(second.eventsUpdated, 0)
        XCTAssertEqual(second.eventsSkipped, 3)
        XCTAssertEqual(target.babies().count, 1)
        XCTAssertEqual(try target.context.count(for: Event.request()), 3)
    }

    func testNewerImportedCopyWins() throws {
        let store = makeStore()
        let baby = try populate(store)
        var file = BackupService.makeBackupFile(store: store)
        let index = try XCTUnwrap(file.events.firstIndex { $0.kind == .bottle })
        file.events[index].amountML = 150
        file.events[index].updatedAt = Date().addingTimeInterval(60)

        let summary = BackupService.importBackup(file, into: store)
        XCTAssertEqual(summary.eventsUpdated, 1)
        XCTAssertEqual(store.lastEvent(of: [.bottle], for: baby)?.record.amountML, 150)
    }

    func testCSVExportHasHeaderAndRows() throws {
        let store = makeStore()
        _ = try populate(store)
        let url = try BackupService.exportCSV(store: store)
        let text = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        let lines = text.split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("amount_ml"))
    }
}
