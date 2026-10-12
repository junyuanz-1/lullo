import Foundation

/// Every kind of thing a caregiver can log.
public enum EventKind: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case sleep
    case nursing
    case bottle
    case solids
    case pumping
    case diaper
    case growth
    case medication
    case temperature
    case symptom
    case vaccine
    case activity
    case fussy
    case note

    public var id: String { rawValue }

    public var category: EventCategory {
        switch self {
        case .sleep: return .sleep
        case .nursing, .bottle, .solids: return .feeding
        case .pumping: return .pumping
        case .diaper: return .diaper
        case .growth: return .growth
        case .medication, .temperature, .symptom, .vaccine: return .health
        case .activity: return .activity
        case .fussy: return .fussy
        case .note: return .note
        }
    }

    /// Kinds that can be started as a live timer.
    public var supportsTimer: Bool {
        switch self {
        case .sleep, .nursing, .bottle, .pumping, .activity: return true
        default: return false
        }
    }

    /// Kinds whose entries span a time range (start + end).
    public var hasDuration: Bool { supportsTimer }

    /// Point-in-time kinds that may also be given an end time. Without one the
    /// entry is a moment, not a running timer.
    public var allowsOptionalEnd: Bool { self == .fussy }

    public var isFeeding: Bool { category == .feeding }
}

public enum EventCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case sleep
    case feeding
    case diaper
    case pumping
    case growth
    case health
    case activity
    case fussy
    case note

    public var id: String { rawValue }

    public var kinds: [EventKind] { EventKind.allCases.filter { $0.category == self } }
}

public enum BreastSide: String, Codable, CaseIterable, Sendable, Hashable {
    case left
    case right

    public var other: BreastSide { self == .left ? .right : .left }
}

public enum BottleContent: String, Codable, CaseIterable, Sendable {
    case formula
    case breastMilk
    case mixed
    case milk
    case other
}

public enum DiaperType: String, Codable, CaseIterable, Sendable {
    case wet
    case dirty
    case mixed
    case dry

    public var isWet: Bool { self == .wet || self == .mixed }
    public var isDirty: Bool { self == .dirty || self == .mixed }
}

/// How much a wet diaper held.
public enum PeeAmount: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

public enum PoopColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case green
    case brown
    case orange
    case black
    case red
    case white
}

public enum PoopConsistency: String, Codable, CaseIterable, Sendable {
    case runny
    case mushy
    case seedy
    case soft
    case formed
    case hard
}

public enum SleepLocation: String, Codable, CaseIterable, Sendable {
    case crib
    case bassinet
    case bed
    case arms
    case stroller
    case car
    case carrier
    case other
}

public enum FoodReaction: String, Codable, CaseIterable, Sendable {
    case loved
    case liked
    case neutral
    case disliked
    case allergic
}

public enum ActivityType: String, Codable, CaseIterable, Sendable {
    case bath
    case tummyTime
    case outdoor
    case play
    case story
    case screenTime
    case skinToSkin
    case brushTeeth
    case massage
    case potty
    case other
}

/// How hard a fussy spell was.
public enum FussIntensity: String, Codable, CaseIterable, Sendable {
    case mild
    case moderate
    case intense
}

/// What seemed to set off a fussy spell. Several can apply.
public enum FussCause: String, Codable, CaseIterable, Sendable {
    case hungry
    case tired
    case gas
    case diaper
    case colic
    case teething
    case unwell
    case overstimulated
    case wantsHolding
    case unknown
}

/// What was tried to settle a fussy spell. Several can apply.
public enum SoothingMethod: String, Codable, CaseIterable, Sendable {
    case holding
    case rocking
    case feeding
    case pacifier
    case whiteNoise
    case swaddling
    case burping
    case diaperChange
    case bath
    case walk
    case singing
    case other
}

public enum Sex: String, Codable, CaseIterable, Sendable {
    case female
    case male
    case unspecified
}
