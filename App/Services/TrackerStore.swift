import BabyCore
import Combine
import CoreData
import SwiftUI
import WidgetKit

/// The app's single entry point for reading and changing data. Every mutation
/// goes through here so widgets, Live Activities and reminders stay in sync.
@MainActor
final class TrackerStore: ObservableObject {
    static let shared = TrackerStore()

    let persistence: PersistenceController
    var context: NSManagedObjectContext { persistence.viewContext }

    @Published var selectedBabyID: UUID? {
        didSet {
            guard oldValue != selectedBabyID else { return }
            AppSettings.selectedBabyID = selectedBabyID
            scheduleSideEffects()
        }
    }

    private var cancellables: Set<AnyCancellable> = []
    private var sideEffectTask: Task<Void, Never>?

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        selectedBabyID = AppSettings.selectedBabyID

        // Changes from CloudKit (another device or a caregiver) arrive here.
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSideEffects() }
            .store(in: &cancellables)
    }

    // MARK: - Babies

    func babies() -> [Baby] {
        let request = Baby.request()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func baby(id: UUID?) -> Baby? {
        guard let id else { return nil }
        let request = Baby.request()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// The selected baby, falling back to the first one.
    var selectedBaby: Baby? { baby(id: selectedBabyID) ?? babies().first }

    @discardableResult
    func addBaby(_ record: BabyRecord) -> Baby {
        let baby = persistence.newBaby(in: context)
        baby.apply(record)
        commit()
        selectedBabyID = record.id
        return baby
    }

    func updateBaby(_ baby: Baby, with record: BabyRecord) {
        var record = record
        record.updatedAt = Date()
        baby.apply(record)
        commit()
    }

    func deleteBaby(_ baby: Baby) {
        let wasSelected = baby.id == selectedBabyID
        context.delete(baby)
        commit()
        if wasSelected { selectedBabyID = babies().first?.id }
    }

    // MARK: - Events

    func event(id: UUID) -> Event? {
        let request = Event.request()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func events(for baby: Baby, since: Date? = nil, kinds: [EventKind]? = nil, limit: Int = 0) -> [Event] {
        let request = Event.request()
        var predicates = [NSPredicate(format: "baby == %@", baby)]
        if let since { predicates.append(NSPredicate(format: "startDate >= %@", since as NSDate)) }
        if let kinds { predicates.append(NSPredicate(format: "kind IN %@", kinds.map(\.rawValue))) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    func lastEvent(of kinds: [EventKind], for baby: Baby) -> Event? {
        events(for: baby, kinds: kinds, limit: 1).first
    }

    func runningTimers(for baby: Baby) -> [Event] {
        let request = Event.request()
        request.predicate = NSPredicate(
            format: "baby == %@ AND endDate == nil AND kind IN %@",
            baby, EventKind.allCases.filter(\.supportsTimer).map(\.rawValue)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func runningTimer(_ kind: EventKind, for baby: Baby) -> Event? {
        runningTimers(for: baby).first { $0.eventKind == kind }
    }

    /// Inserts or updates an event from a value record.
    @discardableResult
    func save(_ record: EventRecord) -> Event? {
        var record = record
        record.updatedAt = Date()
        if let existing = event(id: record.id) {
            existing.apply(record)
            commit()
            return existing
        }
        guard let baby = baby(id: record.babyID) else { return nil }
        if record.authorName == nil { record.authorName = AppSettings.caregiverName }
        let event = persistence.newEvent(for: baby, in: context)
        event.apply(record)
        commit()
        return event
    }

    func delete(_ event: Event) {
        if let id = event.id { NotificationManager.cancelMedicationReminder(eventID: id) }
        context.delete(event)
        commit()
    }

    // MARK: - Timers

    @discardableResult
    func startTimer(_ kind: EventKind, for baby: Baby, activityType: ActivityType? = nil, at date: Date = Date()) -> Event? {
        if kind == .nursing { return startNursing(for: baby, side: nil, at: date) }
        if let running = runningTimer(kind, for: baby), kind != .activity { return running }
        guard let babyID = baby.id else { return nil }
        let record = EventRecord(babyID: babyID, kind: kind, startDate: date, activityType: activityType)
        return save(record)
    }

    /// Starts nursing on `side` (or the suggested side). If a session is
    /// already running, switches it to that side instead.
    @discardableResult
    func startNursing(for baby: Baby, side: BreastSide?, at date: Date = Date()) -> Event? {
        if let running = runningTimer(.nursing, for: baby) {
            mutate(running) { $0.startNursing(side ?? ($0.activeSide ?? .left).other, at: date) }
            return running
        }
        guard let babyID = baby.id else { return nil }
        let last = lastEvent(of: [.nursing], for: baby)?.record
        let chosen = side ?? EventRecord.suggestedNextSide(after: last)
        var record = EventRecord(babyID: babyID, kind: .nursing, startDate: date)
        record.startNursing(chosen, at: date)
        return save(record)
    }

    func setNursingSide(_ side: BreastSide, on event: Event) {
        mutate(event) { record in
            if record.activeSide == side {
                record.pauseNursing()
            } else {
                record.startNursing(side)
            }
        }
    }

    func switchNursingSide(_ event: Event) {
        mutate(event) { $0.switchNursingSide() }
    }

    func toggleNursingPause(_ event: Event) {
        mutate(event) { record in
            if record.activeSide != nil {
                record.pauseNursing()
            } else {
                // Resume on the side that was paused.
                record.startNursing(record.lastSide ?? .left)
            }
        }
    }

    func stopTimer(_ event: Event, at date: Date = Date()) {
        mutate(event) { record in
            if record.kind == .nursing {
                record.finishNursing(at: date)
            } else {
                record.endDate = max(date, record.startDate)
            }
        }
    }

    func logDiaper(_ type: DiaperType, for baby: Baby, at date: Date = Date()) {
        guard let babyID = baby.id else { return }
        save(EventRecord(babyID: babyID, kind: .diaper, startDate: date, diaperType: type))
    }

    private func mutate(_ event: Event, _ change: (inout EventRecord) -> Void) {
        var record = event.record
        change(&record)
        record.updatedAt = Date()
        event.apply(record)
        commit()
    }

    // MARK: - Saving and side effects

    func commit() {
        persistence.save()
        scheduleSideEffects()
    }

    /// Coalesces bursts of changes (e.g. a CloudKit import) into one refresh.
    func scheduleSideEffects() {
        sideEffectTask?.cancel()
        sideEffectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshSideEffects()
        }
    }

    /// Rebuilds the widget snapshot, then updates widgets, Live Activities and reminders from it.
    func refreshSideEffects() {
        let snapshot = makeSnapshot()
        SharedContainer.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        LiveActivityManager.shared.sync(with: snapshot)
        NotificationManager.reschedule(from: snapshot)
        let all = babies()
        TimerAlarms.shared.sync(
            running: all.flatMap { runningTimers(for: $0) }.map(\.record),
            babyNames: Dictionary(all.compactMap { b in b.id.map { ($0, b.displayName) } }, uniquingKeysWith: { a, _ in a })
        )
    }

    func makeSnapshot(now: Date = Date()) -> WidgetSnapshot {
        let classifier = AppSettings.sleepClassifier
        let since = now.addingTimeInterval(-3 * 86_400)
        let babies = babies().compactMap { baby -> BabySnapshot? in
            guard baby.id != nil else { return nil }
            var records = events(for: baby, since: since).map(\.record)
            // Make sure the latest feed, diaper and sleep are present even if older than the window.
            for kinds in [[EventKind.nursing, .bottle, .solids], [.diaper], [.sleep]] {
                if let last = lastEvent(of: kinds, for: baby), (last.startDate ?? now) < since {
                    records.append(last.record)
                }
            }
            records.append(contentsOf: runningTimers(for: baby).filter { ($0.startDate ?? now) < since }.map(\.record))
            return WidgetSnapshotBuilder.make(baby: baby.record, events: records, now: now, classifier: classifier)
        }
        return WidgetSnapshot(
            generatedAt: now,
            selectedBabyID: selectedBaby?.id,
            babies: babies,
            unitSystem: AppSettings.unitSystem
        )
    }

    func appBecameActive() {
        if baby(id: selectedBabyID) == nil { selectedBabyID = babies().first?.id }
        refreshSideEffects()
    }
}
