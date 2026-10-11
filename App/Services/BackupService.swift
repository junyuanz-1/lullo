import BabyCore
import CoreData
import Foundation

/// Export to / import from a portable JSON file, plus a CSV export.
@MainActor
enum BackupService {
    struct ImportSummary {
        var babiesAdded = 0
        var babiesUpdated = 0
        var eventsAdded = 0
        var eventsUpdated = 0
        var eventsSkipped = 0
    }

    static func makeBackupFile(store: TrackerStore) -> BackupFile {
        let babies = store.babies()
        let events = babies.flatMap { store.events(for: $0) }.map(\.record)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return BackupFile(appVersion: version, babies: babies.map(\.record), events: events)
    }

    /// Writes a backup to a temporary file and returns its URL (for the share sheet).
    static func exportBackup(store: TrackerStore) throws -> URL {
        let data = try BackupCodec.encode(makeBackupFile(store: store))
        let url = temporaryURL(name: "InfantTracker-Backup-\(fileDate()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportCSV(store: TrackerStore) throws -> URL {
        let file = makeBackupFile(store: store)
        let csv = CSVExporter.csv(events: file.events, babies: file.babies)
        let url = temporaryURL(name: "InfantTracker-Events-\(fileDate()).csv")
        // UTF-8 BOM so Excel opens Chinese text correctly.
        try (Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)).write(to: url, options: .atomic)
        return url
    }

    static func readBackup(at url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try BackupCodec.decode(Data(contentsOf: url))
    }

    /// Merges a backup into the current data. Records are matched by ID; newer copies win.
    static func importBackup(_ file: BackupFile, into store: TrackerStore) -> ImportSummary {
        var summary = ImportSummary()
        let existingBabies = store.babies()
        let babyPlan = BackupMerge.plan(
            babies: file.babies,
            existingUpdatedAt: Dictionary(existingBabies.compactMap { b in b.id.map { ($0, b.updatedAt ?? .distantPast) } },
                                          uniquingKeysWith: { a, _ in a })
        )
        for record in babyPlan.inserts {
            store.persistence.newBaby(in: store.context).apply(record)
            summary.babiesAdded += 1
        }
        for record in babyPlan.updates {
            store.baby(id: record.id)?.apply(record)
            summary.babiesUpdated += 1
        }
        store.persistence.save()

        let babiesByID = Dictionary(store.babies().compactMap { b in b.id.map { ($0, b) } }, uniquingKeysWith: { a, _ in a })
        let existingEvents = babiesByID.values.flatMap { store.events(for: $0) }
        let eventPlan = BackupMerge.plan(
            events: file.events,
            existingUpdatedAt: Dictionary(existingEvents.compactMap { e in e.id.map { ($0, e.updatedAt ?? .distantPast) } },
                                          uniquingKeysWith: { a, _ in a })
        )
        let eventsByID = Dictionary(existingEvents.compactMap { e in e.id.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        for record in eventPlan.inserts {
            guard let baby = babiesByID[record.babyID] else {
                summary.eventsSkipped += 1
                continue
            }
            store.persistence.newEvent(for: baby, in: store.context).apply(record)
            summary.eventsAdded += 1
        }
        for record in eventPlan.updates {
            eventsByID[record.id]?.apply(record)
            summary.eventsUpdated += 1
        }
        summary.eventsSkipped += eventPlan.skipped
        store.commit()
        if store.selectedBabyID == nil { store.selectedBabyID = store.babies().first?.id }
        return summary
    }

    private static func temporaryURL(name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    private static func fileDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
