import BabyCore
import CoreData

@objc(Baby)
final class Baby: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var birthDate: Date?
    @NSManaged var sex: String?
    @NSManaged var photoData: Data?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var events: NSSet?

    /// Named `request()` to avoid clashing with the inherited `NSManagedObject.fetchRequest()`.
    @nonobjc class func request() -> NSFetchRequest<Baby> {
        NSFetchRequest<Baby>(entityName: "Baby")
    }

    var displayName: String { name?.isEmpty == false ? name! : String(localized: "Baby") }

    var record: BabyRecord {
        BabyRecord(
            id: id ?? UUID(),
            name: name ?? "",
            birthDate: birthDate ?? Date(),
            sex: sex.flatMap(Sex.init(rawValue:)) ?? .unspecified,
            photoData: photoData,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func apply(_ r: BabyRecord) {
        id = r.id
        name = r.name
        birthDate = r.birthDate
        sex = r.sex.rawValue
        photoData = r.photoData
        createdAt = r.createdAt
        updatedAt = r.updatedAt
    }
}

@objc(Event)
final class Event: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var kind: String?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var note: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var authorName: String?
    @NSManaged var sleepLocation: String?
    @NSManaged var leftDuration: Double
    @NSManaged var rightDuration: Double
    @NSManaged var activeSide: String?
    @NSManaged var activeSideStartedAt: Date?
    @NSManaged var lastSide: String?
    @NSManaged var amountML: NSNumber?
    @NSManaged var leftAmountML: NSNumber?
    @NSManaged var rightAmountML: NSNumber?
    @NSManaged var bottleContent: String?
    @NSManaged var foodName: String?
    @NSManaged var foodReaction: String?
    @NSManaged var diaperType: String?
    @NSManaged var poopColor: String?
    @NSManaged var poopConsistency: String?
    @NSManaged var peeAmount: String?
    @NSManaged var hasRash: Bool
    @NSManaged var weightKg: NSNumber?
    @NSManaged var heightCm: NSNumber?
    @NSManaged var headCm: NSNumber?
    @NSManaged var medicationName: String?
    @NSManaged var dosage: String?
    @NSManaged var temperatureC: NSNumber?
    @NSManaged var symptoms: String?
    @NSManaged var vaccineName: String?
    @NSManaged var activityType: String?
    @NSManaged var photoData: Data?
    @NSManaged var baby: Baby?

    @nonobjc class func request() -> NSFetchRequest<Event> {
        NSFetchRequest<Event>(entityName: "Event")
    }

    var eventKind: EventKind { kind.flatMap(EventKind.init(rawValue:)) ?? .note }

    var record: EventRecord {
        EventRecord(
            id: id ?? UUID(),
            babyID: baby?.id ?? UUID(),
            kind: eventKind,
            startDate: startDate ?? Date(),
            endDate: endDate,
            note: note,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date(),
            authorName: authorName,
            sleepLocation: sleepLocation.flatMap(SleepLocation.init(rawValue:)),
            leftDuration: leftDuration,
            rightDuration: rightDuration,
            activeSide: activeSide.flatMap(BreastSide.init(rawValue:)),
            activeSideStartedAt: activeSideStartedAt,
            lastSide: lastSide.flatMap(BreastSide.init(rawValue:)),
            amountML: amountML?.doubleValue,
            leftAmountML: leftAmountML?.doubleValue,
            rightAmountML: rightAmountML?.doubleValue,
            bottleContent: bottleContent.flatMap(BottleContent.init(rawValue:)),
            foodName: foodName,
            foodReaction: foodReaction.flatMap(FoodReaction.init(rawValue:)),
            diaperType: diaperType.flatMap(DiaperType.init(rawValue:)),
            peeAmount: peeAmount.flatMap(PeeAmount.init(rawValue:)),
            poopColor: poopColor.flatMap(PoopColor.init(rawValue:)),
            poopConsistency: poopConsistency.flatMap(PoopConsistency.init(rawValue:)),
            hasRash: hasRash,
            weightKg: weightKg?.doubleValue,
            heightCm: heightCm?.doubleValue,
            headCm: headCm?.doubleValue,
            medicationName: medicationName,
            dosage: dosage,
            temperatureC: temperatureC?.doubleValue,
            symptoms: symptoms,
            vaccineName: vaccineName,
            activityType: activityType.flatMap(ActivityType.init(rawValue:)),
            photoData: photoData
        )
    }

    /// Copies every field except the baby relationship, which the caller sets.
    func apply(_ r: EventRecord) {
        id = r.id
        kind = r.kind.rawValue
        startDate = r.startDate
        endDate = r.endDate
        note = r.note?.nilIfBlank
        createdAt = r.createdAt
        updatedAt = r.updatedAt
        authorName = r.authorName
        sleepLocation = r.sleepLocation?.rawValue
        leftDuration = r.leftDuration
        rightDuration = r.rightDuration
        activeSide = r.activeSide?.rawValue
        activeSideStartedAt = r.activeSideStartedAt
        lastSide = r.lastSide?.rawValue
        amountML = r.amountML.map(NSNumber.init(value:))
        leftAmountML = r.leftAmountML.map(NSNumber.init(value:))
        rightAmountML = r.rightAmountML.map(NSNumber.init(value:))
        bottleContent = r.bottleContent?.rawValue
        foodName = r.foodName?.nilIfBlank
        foodReaction = r.foodReaction?.rawValue
        diaperType = r.diaperType?.rawValue
        peeAmount = r.peeAmount?.rawValue
        poopColor = r.poopColor?.rawValue
        poopConsistency = r.poopConsistency?.rawValue
        hasRash = r.hasRash
        weightKg = r.weightKg.map(NSNumber.init(value:))
        heightCm = r.heightCm.map(NSNumber.init(value:))
        headCm = r.headCm.map(NSNumber.init(value:))
        medicationName = r.medicationName?.nilIfBlank
        dosage = r.dosage?.nilIfBlank
        temperatureC = r.temperatureC.map(NSNumber.init(value:))
        symptoms = r.symptoms?.nilIfBlank
        vaccineName = r.vaccineName?.nilIfBlank
        activityType = r.activityType?.rawValue
        photoData = r.photoData
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
