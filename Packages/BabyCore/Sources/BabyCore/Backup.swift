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
