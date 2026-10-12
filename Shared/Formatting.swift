import BabyCore
import Foundation

/// Locale-aware formatting for durations, amounts and ages.
enum Fmt {
    static func duration(_ seconds: TimeInterval, style: DateComponentsFormatter.UnitsStyle = .abbreviated) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        if seconds < 60 {
            formatter.allowedUnits = [.second]
        } else if seconds < 3600 {
            formatter.allowedUnits = [.minute]
        } else {
            formatter.allowedUnits = [.hour, .minute]
        }
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(0, seconds.rounded(.down))) ?? ""
    }

    /// Stopwatch style, e.g. 1:05:09 or 12:30.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "just now") }
        return String(localized: "\(duration(seconds)) ago")
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    static func volume(_ ml: Double, unit: UnitSystem = AppSettings.unitSystem) -> String {
        switch unit {
        case .metric:
            return String(localized: "\(number(ml, digits: 0)) ml")
        case .imperial:
            return String(localized: "\(number(UnitConversion.ounces(fromML: ml), digits: 1)) oz")
        }
    }

    static func weight(_ kg: Double, unit: UnitSystem = AppSettings.unitSystem) -> String {
        switch unit {
        case .metric:
            return String(localized: "\(number(kg, digits: 2)) kg")
        case .imperial:
            let parts = UnitConversion.poundsAndOunces(fromKg: kg)
            return String(localized: "\(String(parts.pounds)) lb \(number(parts.ounces, digits: 1)) oz")
        }
    }

    static func length(_ cm: Double, unit: UnitSystem = AppSettings.unitSystem) -> String {
        switch unit {
        case .metric:
            return String(localized: "\(number(cm, digits: 1)) cm")
        case .imperial:
            return String(localized: "\(number(UnitConversion.inches(fromCm: cm), digits: 1)) in")
        }
    }

    static func temperature(_ celsius: Double, unit: TemperatureUnit = AppSettings.temperatureUnit) -> String {
        switch unit {
        case .celsius: return "\(number(celsius, digits: 1)) °C"
        case .fahrenheit: return "\(number(UnitConversion.fahrenheit(fromCelsius: celsius), digits: 1)) °F"
        }
    }

    static func percentile(_ p: Double) -> String {
        let clamped = min(99.9, max(0.1, p))
        return String(localized: "\(number(clamped, digits: clamped < 1 || clamped > 99 ? 1 : 0))th percentile")
    }

    static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    /// "3 months, 2 weeks" / "3个月2周"
    static func age(birthDate: Date, at now: Date = Date(), calendar: Calendar = .current) -> String {
        guard now >= birthDate else { return String(localized: "Not born yet") }
        let components = calendar.dateComponents([.year, .month, .weekOfMonth, .day], from: birthDate, to: now)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day]
        if components.year == 0, components.month == 0, components.weekOfMonth == 0, components.day == 0 {
            return String(localized: "Newborn")
        }
        return formatter.string(from: components) ?? ""
    }
}

extension EventRecord {
    /// One-line summary of the details, e.g. "120 ml · Formula" or "L 8m · R 6m".
    func detailText(now: Date = Date()) -> String {
        var parts: [String] = []
        switch kind {
        case .sleep:
            parts.append(Fmt.duration(duration(at: now)))
            if let sleepLocation { parts.append(sleepLocation.title) }
        case .nursing:
            let left = nursingElapsed(.left, at: now)
            let right = nursingElapsed(.right, at: now)
            if left > 0 { parts.append("\(BreastSide.left.shortTitle) \(Fmt.duration(left))") }
            if right > 0 { parts.append("\(BreastSide.right.shortTitle) \(Fmt.duration(right))") }
            if left > 0 && right > 0 { parts.append(String(localized: "Total \(Fmt.duration(left + right))")) }
        case .bottle:
            if let amountML { parts.append(Fmt.volume(amountML)) }
            if let bottleContent { parts.append(bottleContent.title) }
        case .solids:
            if foodName != nil, let amountML { parts.append(Fmt.volume(amountML)) }
            if let foodReaction { parts.append("\(foodReaction.emoji) \(foodReaction.title)") }
        case .pumping:
            if let total = pumpedTotalML { parts.append(Fmt.volume(total)) }
            if let l = leftAmountML, let r = rightAmountML {
                parts.append("\(BreastSide.left.shortTitle) \(Fmt.volume(l)) · \(BreastSide.right.shortTitle) \(Fmt.volume(r))")
            }
            if duration(at: now) > 0 { parts.append(Fmt.duration(duration(at: now))) }
        case .diaper:
            if let peeAmount, diaperType?.isWet == true { parts.append(String(localized: "Pee: \(peeAmount.title)")) }
            if let poopColor, diaperType?.isDirty == true { parts.append(poopColor.title) }
            if let poopConsistency, diaperType?.isDirty == true { parts.append(poopConsistency.title) }
            if hasRash { parts.append(String(localized: "Rash")) }
        case .growth:
            if let weightKg { parts.append(Fmt.weight(weightKg)) }
            if let heightCm { parts.append(Fmt.length(heightCm)) }
            if let headCm { parts.append(String(localized: "Head \(Fmt.length(headCm))")) }
        case .medication:
            if let dosage { parts.append(dosage) }
        case .temperature:
            if let temperatureC { parts.append(Fmt.temperature(temperatureC)) }
        case .symptom:
            if let symptoms { parts.append(symptoms) }
        case .vaccine:
            break
        case .activity:
            if duration(at: now) > 0 { parts.append(Fmt.duration(duration(at: now))) }
        case .note:
            break
        }
        if let note { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}
