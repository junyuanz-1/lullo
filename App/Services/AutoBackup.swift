import BabyCore
import CoreData
import Foundation
import OSLog

/// Daily backups kept on this device (newest 10), so a mistake by anyone the
/// baby is shared with can be undone. They live in Application Support, which
/// is also included in the phone's own iCloud/computer backups.
@MainActor
final class AutoBackup: ObservableObject {
    static let shared = AutoBackup()

    enum Reason: String {
        case daily = "auto"
        case manual
        case beforeRestore = "restore"
    }

    struct Entry: Identifiable, Hashable {
        let url: URL
        let date: Date
        let reason: Reason
        let size: Int64
        var id: URL { url }
    }

    struct RestoreSummary {
        var restored = 0
        var removed = 0
        var skippedBabies = 0
    }

    @Published private(set) var entries: [Entry] = []

    private let directory: URL
    private let logger = Logger(subsystem: "Tinytide", category: "AutoBackup")

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        reload()
    }

    // MARK: Listing

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        )) ?? []
        entries = files.compactMap(Self.entry(for:)).sorted { $0.date > $1.date }
    }

    private static func entry(for url: URL) -> Entry? {
        // <reason>-<milliseconds since 1970>.json
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard url.pathExtension == "json", parts.count == 2,
              let reason = Reason(rawValue: String(parts[0])),
              let millis = TimeInterval(parts[1]) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return Entry(url: url, date: Date(timeIntervalSince1970: millis / 1000), reason: reason, size: size)
    }

    // MARK: Creating

    /// Called when the app becomes active; makes at most one automatic backup a day.
    func backUpIfDue(store: TrackerStore, now: Date = Date()) {
        let lastDaily = entries.first { $0.reason == .daily }?.date
        guard AutoBackupPolicy.isDue(lastBackup: lastDaily, now: now), !store.babies().isEmpty else { return }
        // On a new phone the first babies can arrive before their history; a
        // backup now would hold only part of it (and restoring it would remove the rest).
        guard store.persistence.inMemory || !AppSettings.awaitingFirstCloudImport else { return }
        do {
            try backUp(store: store, reason: .daily, now: now)
        } catch {
            logger.error("Daily backup failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func backUp(store: TrackerStore, reason: Reason, now: Date = Date()) throws -> Entry {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try BackupCodec.encode(BackupService.makeBackupFile(store: store))
        let url = directory.appendingPathComponent("\(reason.rawValue)-\(Int64(now.timeIntervalSince1970 * 1000)).json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        reload()
        prune()
        logger.info("Backup written (\(reason.rawValue), \(data.count) bytes)")
        return entries.first { $0.url == url } ?? Entry(url: url, date: now, reason: reason, size: Int64(data.count))
    }

    /// Keeps the newest daily backups and, separately, the newest manual and
    /// before-restore ones, so a run of restores can't push out the daily history.
    private func prune() {
        let daily = entries.filter { $0.reason == .daily }
        let others = entries.filter { $0.reason != .daily }
        for entry in AutoBackupPolicy.toPrune(daily, date: \.date) + AutoBackupPolicy.toPrune(others, date: \.date) {
            try? FileManager.default.removeItem(at: entry.url)
        }
        reload()
    }

    func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        reload()
    }

    func read(_ entry: Entry) throws -> BackupFile {
        try BackupCodec.decode(Data(contentsOf: entry.url))
    }

    // MARK: Restoring

    /// Rolls every baby in the backup that this user may edit back to the moment
    /// the backup was taken. A backup of the current data is made first, so the
    /// restore itself can be undone. Changes sync to everyone the baby is shared with.
    func restore(_ entry: Entry, store: TrackerStore) throws -> RestoreSummary {
        if !store.persistence.inMemory && AppSettings.awaitingFirstCloudImport { throw BackupService.SyncPending() }
        let file = try read(entry)
        try backUp(store: store, reason: .beforeRestore)

        var summary = RestoreSummary()
        let babies = store.babies()
        let babiesByID = Dictionary(babies.compactMap { b in b.id.map { ($0, b) } }, uniquingKeysWith: { a, _ in a })
        var scope = Set<UUID>()
        for baby in file.babies {
            if let existing = babiesByID[baby.id], !store.persistence.canEdit(existing) {
                summary.skippedBabies += 1
            } else {
                scope.insert(baby.id)
            }
        }
        let currentEvents = babies.filter { $0.id.map(scope.contains) == true }.flatMap { store.events(for: $0) }
        let plan = BackupRollback.plan(
            backup: file,
            currentBabies: babies.map(\.record),
            currentEvents: currentEvents.map(\.record),
            babyIDs: scope
        )

        for record in plan.upsertBabies {
            (store.baby(id: record.id) ?? store.persistence.newBaby(in: store.context)).apply(record)
        }
        store.persistence.save()

        let eventsByID = Dictionary(currentEvents.compactMap { e in e.id.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        for id in plan.deleteEventIDs {
            if let event = eventsByID[id] { store.context.delete(event) }
        }
        for record in plan.upsertEvents {
            if let event = eventsByID[record.id] {
                event.apply(record)
            } else if let baby = store.baby(id: record.babyID) {
                store.persistence.newEvent(for: baby, in: store.context).apply(record)
            } else {
                continue
            }
            summary.restored += 1
        }
        summary.removed = plan.deleteEventIDs.count
        store.commit()
        if store.baby(id: store.selectedBabyID) == nil { store.selectedBabyID = store.babies().first?.id }
        return summary
    }
}
