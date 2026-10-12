import Foundation

/// Flat CSV export of events, for spreadsheets or sharing with a doctor.
/// Values are always metric so the file is unambiguous.
public enum CSVExporter {
    public static let header = [
        "id", "baby", "type", "start", "end", "duration_min",
        "left_min", "right_min", "last_side",
        "amount_ml", "left_ml", "right_ml", "bottle_content", "food", "food_reaction",
        "diaper", "pee_amount", "poop_color", "poop_consistency", "rash",
        "weight_kg", "length_cm", "head_cm",
        "medication", "dosage", "temperature_c", "symptoms", "vaccine",
        "activity", "sleep_location", "note", "author",
    ]

    public static func csv(
        events: [EventRecord],
        babies: [BabyRecord],
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> String {
        let names = Dictionary(babies.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [header.joined(separator: ",")]
        for e in events.sorted(by: { $0.startDate < $1.startDate }) {
            let durationMinutes: String = e.kind.hasDuration ? number(e.duration(at: now) / 60) : ""
            let row: [String] = [
                e.id.uuidString,
                text(names[e.babyID]),
                e.kind.rawValue,
                formatter.string(from: e.startDate),
                e.endDate.map(formatter.string(from:)) ?? "",
                durationMinutes,
                e.kind == .nursing ? number(e.nursingElapsed(.left, at: now) / 60) : "",
                e.kind == .nursing ? number(e.nursingElapsed(.right, at: now) / 60) : "",
                e.lastSide?.rawValue ?? "",
                number(e.amountML),
                number(e.leftAmountML),
                number(e.rightAmountML),
                e.bottleContent?.rawValue ?? "",
                text(e.foodName),
                e.foodReaction?.rawValue ?? "",
                e.diaperType?.rawValue ?? "",
                e.diaperType?.isWet == true ? (e.peeAmount?.rawValue ?? "") : "",
                e.poopColor?.rawValue ?? "",
                e.poopConsistency?.rawValue ?? "",
                e.kind == .diaper ? (e.hasRash ? "yes" : "no") : "",
                number(e.weightKg, digits: 3),
                number(e.heightCm),
                number(e.headCm),
                text(e.medicationName),
                text(e.dosage),
                number(e.temperatureC),
                text(e.symptoms),
                text(e.vaccineName),
                e.activityType?.rawValue ?? "",
                e.sleepLocation?.rawValue ?? "",
                text(e.note),
                text(e.authorName),
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(digits)f", value)
    }

    /// Free text typed by a user. A leading `=`, `+`, `-`, `@`, tab or CR would make
    /// a spreadsheet run it as a formula, so it gets a `'` prefix and shows as text.
    /// Only used for text columns, so negative numbers stay numbers.
    static func text(_ value: String?) -> String {
        guard let value, let first = value.unicodeScalars.first else { return "" }
        let formulaStarts: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        return formulaStarts.contains(first) ? "'" + value : value
    }

    static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
