import Foundation

/// A complete, portable export of all data. Written as JSON so it can be moved
/// between phones (AirDrop, Files, email) and re-imported.
public struct BackupFile: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let fileExtension = "babylog"

    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String?
    public var babies: [BabyRecord]
    public var events: [EventRecord]

    public init(
        formatVersion: Int = BackupFile.currentFormatVersion,
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        babies: [BabyRecord],
        events: [EventRecord]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.babies = babies
        self.events = events
    }
}

public enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case corrupt(String)
}

public enum BackupCodec {
    public static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCoding.string(from: date))
        }
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let string = try container.decode(String.self)
            guard let date = DateCoding.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
        let file: BackupFile
        do {
            file = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.corrupt(String(describing: error))
        }
        guard file.formatVersion <= BackupFile.currentFormatVersion else {
            throw BackupError.unsupportedVersion(file.formatVersion)
        }
        return file
    }
}

enum DateCoding {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// What an import will do to the existing data. Records are matched by `id`;
/// an existing record is only replaced when the imported copy is newer.
public struct ImportPlan<Record: Identifiable>: Sendable where Record: Sendable, Record.ID == UUID {
    public var inserts: [Record] = []
    public var updates: [Record] = []
    public var skipped = 0

    public var changeCount: Int { inserts.count + updates.count }
}

public enum BackupMerge {
    public static func plan(
        babies incoming: [BabyRecord],
        existingUpdatedAt: [UUID: Date]
    ) -> ImportPlan<BabyRecord> {
        plan(incoming, existingUpdatedAt: existingUpdatedAt, updatedAt: \.updatedAt)
    }

    public static func plan(
        events incoming: [EventRecord],
        existingUpdatedAt: [UUID: Date]
    ) -> ImportPlan<EventRecord> {
        plan(incoming, existingUpdatedAt: existingUpdatedAt, updatedAt: \.updatedAt)
    }

    static func plan<R>(
        _ incoming: [R],
        existingUpdatedAt: [UUID: Date],
        updatedAt: KeyPath<R, Date>
    ) -> ImportPlan<R> where R: Identifiable & Sendable, R.ID == UUID {
        var result = ImportPlan<R>()
        var seen = Set<UUID>()
        for record in incoming where seen.insert(record.id).inserted {
            if let existing = existingUpdatedAt[record.id] {
                // Allow for the millisecond precision of the file format.
                if record[keyPath: updatedAt].timeIntervalSince(existing) > 0.001 {
                    result.updates.append(record)
                } else {
                    result.skipped += 1
                }
            } else {
                result.inserts.append(record)
            }
        }
        return result
    }
}

/// What restoring a backup changes, as "roll back to that moment": for every
/// baby in scope, entries added since the backup are deleted, edited ones are
/// put back and deleted ones come back. Babies not in the backup are left alone.
public struct RollbackPlan: Sendable {
    public var upsertBabies: [BabyRecord] = []
    public var upsertEvents: [EventRecord] = []
    public var deleteEventIDs: [UUID] = []
    public var unchangedEvents = 0

    public var changeCount: Int { upsertBabies.count + upsertEvents.count + deleteEventIDs.count }
}

public enum BackupRollback {
    /// - Parameters:
    ///   - babyIDs: the babies to roll back (for example only those this user may edit).
    ///   - now: stamped as `updatedAt` on everything written, so the restored copy
    ///     wins over older copies on other devices.
    public static func plan(
        backup: BackupFile,
        currentBabies: [BabyRecord],
        currentEvents: [EventRecord],
        babyIDs: Set<UUID>,
        now: Date = Date()
    ) -> RollbackPlan {
        var plan = RollbackPlan()
        let babiesByID = Dictionary(currentBabies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for baby in backup.babies where babyIDs.contains(baby.id) {
            if let current = babiesByID[baby.id], sameContent(current, baby) { continue }
            var restored = baby
            restored.updatedAt = now
            plan.upsertBabies.append(restored)
        }

        let eventsByID = Dictionary(currentEvents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var kept = Set<UUID>()
        for event in backup.events where babyIDs.contains(event.babyID) && kept.insert(event.id).inserted {
            if let current = eventsByID[event.id], sameContent(current, event) {
                plan.unchangedEvents += 1
                continue
            }
            var restored = event
            restored.updatedAt = now
            plan.upsertEvents.append(restored)
        }
        plan.deleteEventIDs = currentEvents
            .filter { babyIDs.contains($0.babyID) && !kept.contains($0.id) }
            .map(\.id)
        return plan
    }

    private static func sameContent(_ a: BabyRecord, _ b: BabyRecord) -> Bool {
        var a = a, b = b
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        a.birthDate = rounded(a.birthDate); b.birthDate = rounded(b.birthDate)
        a.createdAt = rounded(a.createdAt); b.createdAt = rounded(b.createdAt)
        return a == b
    }

    private static func sameContent(_ a: EventRecord, _ b: EventRecord) -> Bool {
        normalized(a) == normalized(b)
    }

    /// Backups store milliseconds; compare dates at that precision.
    private static func normalized(_ r: EventRecord) -> EventRecord {
        var r = r
        r.updatedAt = .distantPast
        r.startDate = rounded(r.startDate)
        r.endDate = r.endDate.map(rounded)
        r.createdAt = rounded(r.createdAt)
        r.activeSideStartedAt = r.activeSideStartedAt.map(rounded)
        r.leftDuration = (r.leftDuration * 1000).rounded() / 1000
        r.rightDuration = (r.rightDuration * 1000).rounded() / 1000
        return r
    }

    private static func rounded(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

/// Rules for the automatic daily backups kept on the device.
public enum AutoBackupPolicy {
    public static let keepCount = 10

    /// One automatic backup per calendar day.
    public static func isDue(lastBackup: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastBackup else { return true }
        return !calendar.isDate(lastBackup, inSameDayAs: now) || lastBackup > now
    }

    /// The items to delete so that only the newest `keep` remain.
    public static func toPrune<T>(_ items: [T], date: (T) -> Date, keep: Int = keepCount) -> [T] {
        Array(items.sorted { date($0) > date($1) }.dropFirst(keep))
    }
}
