import BabyCore
import CoreData
import XCTest
@testable import Tinytide

@MainActor
final class TrackerStoreTests: XCTestCase {
    private var store: TrackerStore!

    override func setUp() async throws {
        AppSettings.selectedBabyID = nil
        store = TrackerStore(persistence: PersistenceController(inMemory: true))
    }

    private func makeBaby(_ name: String = "Mia") -> Baby {
        store.addBaby(BabyRecord(name: name, birthDate: Date().addingTimeInterval(-90 * 86_400), sex: .female))
    }

    func testAddBabySelectsIt() {
        let baby = makeBaby()
        XCTAssertEqual(store.babies().count, 1)
        XCTAssertEqual(store.selectedBabyID, baby.id)
        XCTAssertEqual(store.selectedBaby, baby)
    }

    func testSleepTimerStartsOnceAndStops() throws {
        let baby = makeBaby()
        let first = try XCTUnwrap(store.startTimer(.sleep, for: baby))
        let second = store.startTimer(.sleep, for: baby)
        XCTAssertEqual(first, second, "Starting sleep twice should return the running timer")
        XCTAssertEqual(store.runningTimers(for: baby).count, 1)

        store.stopTimer(first)
        XCTAssertNotNil(first.endDate)
        XCTAssertTrue(store.runningTimers(for: baby).isEmpty)
    }

    func testFussyDetailsAreStoredAndNeverRunAsATimer() throws {
        let baby = makeBaby()
        let babyID = try XCTUnwrap(baby.id)
        var record = EventRecord(babyID: babyID, kind: .fussy, startDate: Date(),
                                 fussIntensity: .moderate, fussCauses: [.gas, .tired], soothingMethods: [.rocking])
        let event = try XCTUnwrap(store.save(record))
        XCTAssertEqual(event.fussCauses, "tired,gas", "Stored in declaration order")
        XCTAssertEqual(event.record.fussCauses, [.tired, .gas])
        XCTAssertEqual(event.record.soothingMethods, [.rocking])
        XCTAssertEqual(event.record.fussIntensity, .moderate)
        XCTAssertTrue(store.runningTimers(for: baby).isEmpty, "A fussy moment without an end is not a running timer")

        record = event.record
        record.fussCauses = []
        store.save(record)
        XCTAssertNil(event.fussCauses, "Clearing every choice clears the field")
    }

    func testOnlyARecentUnendedFussySpellCanBeEnded() throws {
        let baby = makeBaby()
        let babyID = try XCTUnwrap(baby.id)
        let now = Date()
        store.save(EventRecord(babyID: babyID, kind: .fussy, startDate: now.addingTimeInterval(-5 * 3600)))
        XCTAssertNil(store.openFussy(for: baby, now: now), "Over 4 hours old: a moment, not a spell to end")

        let open = try XCTUnwrap(store.save(EventRecord(babyID: babyID, kind: .fussy, startDate: now.addingTimeInterval(-20 * 60))))
        XCTAssertEqual(store.openFussy(for: baby, now: now), open)

        store.stopTimer(open, at: now)
        XCTAssertEqual(open.record.duration(), 20 * 60, accuracy: 1)
        XCTAssertNil(store.openFussy(for: baby, now: now))
    }

    func testNursingUsesSuggestedSideAndSwitches() throws {
        let baby = makeBaby()
        let session = try XCTUnwrap(store.startNursing(for: baby, side: nil))
        XCTAssertEqual(session.record.activeSide, .left, "First ever feed starts on the left")

        store.switchNursingSide(session)
        XCTAssertEqual(session.record.activeSide, .right)

        store.setNursingSide(.right, on: session)
        XCTAssertTrue(session.record.isNursingPaused, "Tapping the running side pauses it")

        store.toggleNursingPause(session)
        XCTAssertEqual(session.record.activeSide, .right, "Resume continues on the paused side")

        store.stopTimer(session)
        XCTAssertFalse(session.record.isOngoing)
        XCTAssertEqual(session.record.lastSide, .right)

        let next = try XCTUnwrap(store.startNursing(for: baby, side: nil))
        XCTAssertNotEqual(next, session)
        XCTAssertEqual(next.record.activeSide, .left, "Next feed suggests the other side")
    }

    func testStartingNursingWhileRunningSwitchesSide() throws {
        let baby = makeBaby()
        let session = try XCTUnwrap(store.startNursing(for: baby, side: .right))
        let again = try XCTUnwrap(store.startNursing(for: baby, side: .left))
        XCTAssertEqual(session, again)
        XCTAssertEqual(again.record.activeSide, .left)
    }

    func testSaveUpsertsAndStampsAuthor() throws {
        SharedContainer.defaults.set("Dad", forKey: SettingsKey.caregiverName)
        defer { SharedContainer.defaults.removeObject(forKey: SettingsKey.caregiverName) }

        let baby = makeBaby()
        var record = EventRecord(babyID: try XCTUnwrap(baby.id), kind: .bottle, startDate: Date(), amountML: 90)
        let event = try XCTUnwrap(store.save(record))
        XCTAssertEqual(event.record.authorName, "Dad")

        record = event.record
        record.amountML = 120
        store.save(record)
        let events = store.events(for: baby)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.record.amountML, 120)
    }

    func testDeletingBabyCascadesToEvents() {
        let baby = makeBaby()
        store.logDiaper(.wet, for: baby)
        store.logDiaper(.dirty, for: baby)
        store.deleteBaby(baby)

        let request = Event.request()
        XCTAssertEqual(try store.context.count(for: request), 0)
        XCTAssertNil(store.selectedBabyID)
    }

    func testEventsFilterByKindAndBaby() {
        let mia = makeBaby("Mia")
        let leo = makeBaby("Leo")
        store.logDiaper(.wet, for: mia)
        store.startTimer(.sleep, for: mia)
        store.logDiaper(.dirty, for: leo)

        XCTAssertEqual(store.events(for: mia).count, 2)
        XCTAssertEqual(store.events(for: mia, kinds: [.diaper]).count, 1)
        XCTAssertEqual(store.lastEvent(of: [.diaper], for: leo)?.record.diaperType, .dirty)
    }

    func testPeeAmountIsStored() throws {
        let baby = makeBaby()
        let record = EventRecord(babyID: try XCTUnwrap(baby.id), kind: .diaper, startDate: Date(), diaperType: .wet, peeAmount: .medium)
        let event = try XCTUnwrap(store.save(record))
        XCTAssertEqual(event.record.peeAmount, .medium)
    }

    func testStoppingFromElsewhereRebasesAnOpenDraft() throws {
        // What the entry editor does when a running sleep is stopped from the Lock Screen.
        let baby = makeBaby()
        let sleep = try XCTUnwrap(store.startTimer(.sleep, for: baby))
        let base = sleep.record
        var draft = base
        draft.note = "edited in the sheet"

        store.stopTimer(sleep)
        let merged = draft.rebased(onto: sleep.record, from: base)
        XCTAssertNotNil(merged.endDate)
        XCTAssertEqual(merged.note, "edited in the sheet")
    }

    func testSnapshotReflectsState() throws {
        let baby = makeBaby()
        store.logDiaper(.mixed, for: baby)
        store.startTimer(.sleep, for: baby)

        let snapshot = store.makeSnapshot()
        let entry = try XCTUnwrap(snapshot.baby(baby.id))
        XCTAssertEqual(entry.name, "Mia")
        XCTAssertEqual(entry.lastDiaper?.type, .mixed)
        XCTAssertNotNil(entry.runningSleep)
        XCTAssertNil(entry.awakeSince)
        XCTAssertEqual(entry.today.wetDiapers, 1)
        XCTAssertEqual(entry.today.dirtyDiapers, 1)
    }
}
