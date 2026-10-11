import Foundation

/// Plain value representation of a baby profile. Used for backups, widgets and
/// any logic that should not depend on Core Data.
public struct BabyRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var birthDate: Date
    public var sex: Sex
    public var photoData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        birthDate: Date,
        sex: Sex = .unspecified,
        photoData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.sex = sex
        self.photoData = photoData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func ageInDays(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: birthDate)
        let end = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// Age in (average) months, used for growth percentiles and wake windows.
    public func ageInMonths(at date: Date = Date()) -> Double {
        max(0, date.timeIntervalSince(birthDate) / (86_400 * 30.4375))
    }
}

/// Plain value representation of one logged event. Fields that do not apply to
/// the event's `kind` are left `nil`.
public struct EventRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var babyID: UUID
    public var kind: EventKind
    public var startDate: Date
    /// `nil` while a timer is running.
    public var endDate: Date?
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var authorName: String?

    // Sleep
    public var sleepLocation: SleepLocation?

    // Nursing (accumulated seconds per side, plus the side that is currently running)
    public var leftDuration: TimeInterval
    public var rightDuration: TimeInterval
    public var activeSide: BreastSide?
    public var activeSideStartedAt: Date?
    public var lastSide: BreastSide?

    // Bottle / pumping / solids
    public var amountML: Double?
    public var leftAmountML: Double?
    public var rightAmountML: Double?
    public var bottleContent: BottleContent?
    public var foodName: String?
    public var foodReaction: FoodReaction?

    // Diaper
    public var diaperType: DiaperType?
    public var poopColor: PoopColor?
    public var poopConsistency: PoopConsistency?
    public var hasRash: Bool

    // Growth
    public var weightKg: Double?
    public var heightCm: Double?
    public var headCm: Double?

    // Health
    public var medicationName: String?
    public var dosage: String?
    public var temperatureC: Double?
    public var symptoms: String?
    public var vaccineName: String?

    // Activity
    public var activityType: ActivityType?

    public var photoData: Data?

    public init(
        id: UUID = UUID(),
        babyID: UUID,
        kind: EventKind,
        startDate: Date,
        endDate: Date? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        authorName: String? = nil,
        sleepLocation: SleepLocation? = nil,
        leftDuration: TimeInterval = 0,
        rightDuration: TimeInterval = 0,
        activeSide: BreastSide? = nil,
        activeSideStartedAt: Date? = nil,
        lastSide: BreastSide? = nil,
        amountML: Double? = nil,
        leftAmountML: Double? = nil,
        rightAmountML: Double? = nil,
        bottleContent: BottleContent? = nil,
        foodName: String? = nil,
        foodReaction: FoodReaction? = nil,
        diaperType: DiaperType? = nil,
        poopColor: PoopColor? = nil,
        poopConsistency: PoopConsistency? = nil,
        hasRash: Bool = false,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        headCm: Double? = nil,
        medicationName: String? = nil,
        dosage: String? = nil,
        temperatureC: Double? = nil,
        symptoms: String? = nil,
        vaccineName: String? = nil,
        activityType: ActivityType? = nil,
        photoData: Data? = nil
    ) {
        self.id = id
        self.babyID = babyID
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.authorName = authorName
        self.sleepLocation = sleepLocation
        self.leftDuration = leftDuration
        self.rightDuration = rightDuration
        self.activeSide = activeSide
        self.activeSideStartedAt = activeSideStartedAt
        self.lastSide = lastSide
        self.amountML = amountML
        self.leftAmountML = leftAmountML
        self.rightAmountML = rightAmountML
        self.bottleContent = bottleContent
        self.foodName = foodName
        self.foodReaction = foodReaction
        self.diaperType = diaperType
        self.poopColor = poopColor
        self.poopConsistency = poopConsistency
        self.hasRash = hasRash
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.headCm = headCm
        self.medicationName = medicationName
        self.dosage = dosage
        self.temperatureC = temperatureC
        self.symptoms = symptoms
        self.vaccineName = vaccineName
        self.activityType = activityType
        self.photoData = photoData
    }

    /// Tolerant decoding so backups written by older or newer versions still import.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        babyID = try c.decode(UUID.self, forKey: .babyID)
        kind = try c.decode(EventKind.self, forKey: .kind)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? startDate
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
        sleepLocation = try? c.decodeIfPresent(SleepLocation.self, forKey: .sleepLocation)
        leftDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .leftDuration) ?? 0
        rightDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .rightDuration) ?? 0
        activeSide = try? c.decodeIfPresent(BreastSide.self, forKey: .activeSide)
        activeSideStartedAt = try c.decodeIfPresent(Date.self, forKey: .activeSideStartedAt)
        lastSide = try? c.decodeIfPresent(BreastSide.self, forKey: .lastSide)
        amountML = try c.decodeIfPresent(Double.self, forKey: .amountML)
        leftAmountML = try c.decodeIfPresent(Double.self, forKey: .leftAmountML)
        rightAmountML = try c.decodeIfPresent(Double.self, forKey: .rightAmountML)
        bottleContent = try? c.decodeIfPresent(BottleContent.self, forKey: .bottleContent)
        foodName = try c.decodeIfPresent(String.self, forKey: .foodName)
        foodReaction = try? c.decodeIfPresent(FoodReaction.self, forKey: .foodReaction)
        diaperType = try? c.decodeIfPresent(DiaperType.self, forKey: .diaperType)
        poopColor = try? c.decodeIfPresent(PoopColor.self, forKey: .poopColor)
        poopConsistency = try? c.decodeIfPresent(PoopConsistency.self, forKey: .poopConsistency)
        hasRash = try c.decodeIfPresent(Bool.self, forKey: .hasRash) ?? false
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        headCm = try c.decodeIfPresent(Double.self, forKey: .headCm)
        medicationName = try c.decodeIfPresent(String.self, forKey: .medicationName)
        dosage = try c.decodeIfPresent(String.self, forKey: .dosage)
        temperatureC = try c.decodeIfPresent(Double.self, forKey: .temperatureC)
        symptoms = try c.decodeIfPresent(String.self, forKey: .symptoms)
        vaccineName = try c.decodeIfPresent(String.self, forKey: .vaccineName)
        activityType = try? c.decodeIfPresent(ActivityType.self, forKey: .activityType)
        photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)
    }

    public var isOngoing: Bool { kind.supportsTimer && endDate == nil }

    /// Wall-clock duration (end − start), or up to `now` for a running timer.
    /// For nursing this is the sum of both sides instead.
    public func duration(at now: Date = Date()) -> TimeInterval {
        if kind == .nursing { return nursingTotal(at: now) }
        guard kind.hasDuration else { return 0 }
        return max(0, (endDate ?? now).timeIntervalSince(startDate))
    }

    /// The end of the event, or `now` if it is still running. Point-in-time
    /// events end when they start.
    public func effectiveEnd(at now: Date = Date()) -> Date {
        if kind.hasDuration { return endDate ?? max(now, startDate) }
        return startDate
    }

    /// Total of both pumped sides, falling back to `amountML`.
    public var pumpedTotalML: Double? {
        if leftAmountML == nil && rightAmountML == nil { return amountML }
        return (leftAmountML ?? 0) + (rightAmountML ?? 0)
    }
}
