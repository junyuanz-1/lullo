import BabyCore
import SwiftUI

// Localized names, icons and colours for the BabyCore enums. Shared by the app
// and the widget extension.

extension EventKind {
    var title: String {
        switch self {
        case .sleep: return String(localized: "Sleep")
        case .nursing: return String(localized: "Nursing")
        case .bottle: return String(localized: "Bottle")
        case .solids: return String(localized: "Solids")
        case .pumping: return String(localized: "Pumping")
        case .diaper: return String(localized: "Diaper")
        case .growth: return String(localized: "Growth")
        case .medication: return String(localized: "Medication")
        case .temperature: return String(localized: "Temperature")
        case .symptom: return String(localized: "Symptom")
        case .vaccine: return String(localized: "Vaccine")
        case .activity: return String(localized: "Activity")
        case .fussy: return String(localized: "Fussy")
        case .note: return String(localized: "Note")
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .nursing: return "heart.fill"
        case .bottle: return "waterbottle.fill"
        case .solids: return "fork.knife"
        case .pumping: return "drop.fill"
        case .diaper: return "leaf.fill"
        case .growth: return "ruler.fill"
        case .medication: return "pills.fill"
        case .temperature: return "thermometer.medium"
        case .symptom: return "stethoscope"
        case .vaccine: return "syringe.fill"
        case .activity: return "figure.play"
        case .fussy: return "cloud.rain.fill"
        case .note: return "note.text"
        }
    }

    var color: Color {
        switch self {
        case .sleep: return .indigo
        case .nursing: return .pink
        case .bottle: return .orange
        case .solids: return .green
        case .pumping: return .purple
        case .diaper: return .teal
        case .growth: return .blue
        case .medication, .temperature, .symptom, .vaccine: return .red
        case .activity: return .mint
        // Storm-cloud slate: apart from the diaper teal and sleep indigo in the schedule chart.
        case .fussy: return Color(red: 0.42, green: 0.5, blue: 0.62)
        case .note: return .gray
        }
    }
}

extension EventKind {
    /// Forms that open half-height, so Save is close at hand (drag up for more).
    var prefersCompactSheet: Bool {
        switch self {
        case .diaper, .note, .fussy: return true
        default: return false
        }
    }
}

extension EventCategory {
    var title: String {
        switch self {
        case .sleep: return String(localized: "Sleep")
        case .feeding: return String(localized: "Feeding")
        case .diaper: return String(localized: "Diaper")
        case .pumping: return String(localized: "Pumping")
        case .growth: return String(localized: "Growth")
        case .health: return String(localized: "Health")
        case .activity: return String(localized: "Activity")
        case .fussy: return String(localized: "Fussy")
        case .note: return String(localized: "Note")
        }
    }
}

extension BreastSide {
    var title: String {
        switch self {
        case .left: return String(localized: "Left")
        case .right: return String(localized: "Right")
        }
    }

    var shortTitle: String {
        switch self {
        case .left: return String(localized: "L", comment: "Short for left breast")
        case .right: return String(localized: "R", comment: "Short for right breast")
        }
    }
}

extension BottleContent {
    var title: String {
        switch self {
        case .formula: return String(localized: "Formula")
        case .breastMilk: return String(localized: "Breast Milk")
        case .mixed: return String(localized: "Mixed")
        case .milk: return String(localized: "Milk")
        case .other: return String(localized: "Other")
        }
    }
}

extension DiaperType {
    var title: String {
        switch self {
        case .wet: return String(localized: "Wet")
        case .dirty: return String(localized: "Dirty")
        case .mixed: return String(localized: "Wet + Dirty")
        case .dry: return String(localized: "Dry")
        }
    }

    var systemImage: String {
        switch self {
        case .wet: return "drop.fill"
        case .dirty: return "circle.hexagongrid.fill"
        case .mixed: return "drop.circle.fill"
        case .dry: return "sun.max.fill"
        }
    }
}

extension PeeAmount {
    var title: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
}

extension PoopColor {
    var title: String {
        switch self {
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .brown: return String(localized: "Brown")
        case .orange: return String(localized: "Orange")
        case .black: return String(localized: "Black")
        case .red: return String(localized: "Red")
        case .white: return String(localized: "White / Pale")
        }
    }

    var swatch: Color {
        switch self {
        case .yellow: return Color(red: 0.93, green: 0.78, blue: 0.25)
        case .green: return Color(red: 0.42, green: 0.55, blue: 0.24)
        case .brown: return Color(red: 0.47, green: 0.31, blue: 0.16)
        case .orange: return Color(red: 0.88, green: 0.52, blue: 0.2)
        case .black: return Color(white: 0.12)
        case .red: return Color(red: 0.75, green: 0.15, blue: 0.15)
        case .white: return Color(white: 0.9)
        }
    }

    /// Colours a paediatrician should hear about.
    var needsAttention: Bool { self == .black || self == .red || self == .white }
}

extension PoopConsistency {
    var title: String {
        switch self {
        case .runny: return String(localized: "Runny")
        case .mushy: return String(localized: "Mushy")
        case .seedy: return String(localized: "Seedy")
        case .soft: return String(localized: "Soft")
        case .formed: return String(localized: "Formed")
        case .hard: return String(localized: "Hard")
        }
    }
}

extension SleepLocation {
    var title: String {
        switch self {
        case .crib: return String(localized: "Crib")
        case .bassinet: return String(localized: "Bassinet")
        case .bed: return String(localized: "Bed")
        case .arms: return String(localized: "In Arms")
        case .stroller: return String(localized: "Stroller")
        case .car: return String(localized: "Car Seat")
        case .carrier: return String(localized: "Carrier")
        case .other: return String(localized: "Other")
        }
    }
}

extension FoodReaction {
    var title: String {
        switch self {
        case .loved: return String(localized: "Loved it")
        case .liked: return String(localized: "Liked it")
        case .neutral: return String(localized: "Neutral")
        case .disliked: return String(localized: "Disliked it")
        case .allergic: return String(localized: "Allergic reaction")
        }
    }

    var emoji: String {
        switch self {
        case .loved: return "😍"
        case .liked: return "🙂"
        case .neutral: return "😐"
        case .disliked: return "😖"
        case .allergic: return "⚠️"
        }
    }
}

extension ActivityType {
    var title: String {
        switch self {
        case .bath: return String(localized: "Bath")
        case .tummyTime: return String(localized: "Tummy Time")
        case .outdoor: return String(localized: "Outdoor")
        case .play: return String(localized: "Play")
        case .story: return String(localized: "Story Time")
        case .screenTime: return String(localized: "Screen Time")
        case .skinToSkin: return String(localized: "Skin to Skin")
        case .brushTeeth: return String(localized: "Brush Teeth")
        case .massage: return String(localized: "Massage")
        case .potty: return String(localized: "Potty")
        case .other: return String(localized: "Other")
        }
    }

    var systemImage: String {
        switch self {
        case .bath: return "bathtub.fill"
        case .tummyTime: return "figure.child"
        case .outdoor: return "sun.max.fill"
        case .play: return "teddybear.fill"
        case .story: return "book.fill"
        case .screenTime: return "tv.fill"
        case .skinToSkin: return "hands.and.sparkles.fill"
        case .brushTeeth: return "mouth.fill"
        case .massage: return "hand.raised.fill"
        case .potty: return "toilet.fill"
        case .other: return "star.fill"
        }
    }
}

extension FussIntensity {
    var title: String {
        switch self {
        case .mild: return String(localized: "Mild")
        case .moderate: return String(localized: "Moderate")
        case .intense: return String(localized: "Intense")
        }
    }
}

extension FussCause {
    var title: String {
        switch self {
        case .hungry: return String(localized: "Hungry")
        case .tired: return String(localized: "Tired")
        case .gas: return String(localized: "Gas / Spit-up")
        case .diaper: return String(localized: "Diaper")
        case .colic: return String(localized: "Colic")
        case .teething: return String(localized: "Teething")
        case .unwell: return String(localized: "Unwell")
        case .overstimulated: return String(localized: "Overstimulated")
        case .wantsHolding: return String(localized: "Wants Holding")
        case .unknown: return String(localized: "Not Sure")
        }
    }
}

extension SoothingMethod {
    var title: String {
        switch self {
        case .holding: return String(localized: "Holding")
        case .rocking: return String(localized: "Rocking")
        case .feeding: return String(localized: "Nursing / Bottle")
        case .pacifier: return String(localized: "Pacifier")
        case .whiteNoise: return String(localized: "White Noise")
        case .swaddling: return String(localized: "Swaddling")
        case .burping: return String(localized: "Burping")
        case .diaperChange: return String(localized: "Diaper Change")
        case .bath: return String(localized: "Bath")
        case .walk: return String(localized: "Walk / Stroller")
        case .singing: return String(localized: "Singing / Talking")
        case .other: return String(localized: "Other")
        }
    }
}

extension Sex {
    var title: String {
        switch self {
        case .female: return String(localized: "Girl")
        case .male: return String(localized: "Boy")
        case .unspecified: return String(localized: "Not Set")
        }
    }
}

extension UnitSystem {
    var title: String {
        switch self {
        case .metric: return String(localized: "Metric (ml, kg, cm)")
        case .imperial: return String(localized: "Imperial (oz, lb, in)")
        }
    }
}

extension TemperatureUnit {
    var title: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

extension GrowthMetric {
    var title: String {
        switch self {
        case .weight: return String(localized: "Weight")
        case .length: return String(localized: "Length")
        case .headCircumference: return String(localized: "Head")
        }
    }
}

extension EventRecord {
    /// Title shown in lists: the kind, refined by the most useful detail.
    var displayTitle: String {
        switch kind {
        case .activity: return activityType?.title ?? kind.title
        case .diaper: return diaperType.map { String(localized: "Diaper · \($0.title)") } ?? kind.title
        case .medication: return medicationName ?? kind.title
        case .vaccine: return vaccineName ?? kind.title
        case .solids: return foodName ?? kind.title
        case .fussy: return fussIntensity.map { String(localized: "Fussy · \($0.title)") } ?? kind.title
        default: return kind.title
        }
    }

    var displayImage: String {
        if kind == .activity, let activityType { return activityType.systemImage }
        return kind.systemImage
    }
}
