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
        assign(self, \.id, r.id)
        assign(self, \.name, r.name)
        assign(self, \.birthDate, r.birthDate)
        assign(self, \.sex, r.sex.rawValue)
        assign(self, \.photoData, r.photoData)
        assign(self, \.createdAt, r.createdAt)
        assign(self, \.updatedAt, r.updatedAt)
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
    /// Only fields whose value differs are assigned (see `assign`).
    func apply(_ r: EventRecord) {
        assign(self, \.id, r.id)
        assign(self, \.kind, r.kind.rawValue)
        assign(self, \.startDate, r.startDate)
        assign(self, \.endDate, r.endDate)
        assign(self, \.note, r.note?.nilIfBlank)
        assign(self, \.createdAt, r.createdAt)
        assign(self, \.updatedAt, r.updatedAt)
        assign(self, \.authorName, r.authorName)
        assign(self, \.sleepLocation, r.sleepLocation?.rawValue)
        assign(self, \.leftDuration, r.leftDuration)
        assign(self, \.rightDuration, r.rightDuration)
        assign(self, \.activeSide, r.activeSide?.rawValue)
        assign(self, \.activeSideStartedAt, r.activeSideStartedAt)
        assign(self, \.lastSide, r.lastSide?.rawValue)
        assign(self, \.amountML, r.amountML.map(NSNumber.init(value:)))
        assign(self, \.leftAmountML, r.leftAmountML.map(NSNumber.init(value:)))
        assign(self, \.rightAmountML, r.rightAmountML.map(NSNumber.init(value:)))
        assign(self, \.bottleContent, r.bottleContent?.rawValue)
        assign(self, \.foodName, r.foodName?.nilIfBlank)
        assign(self, \.foodReaction, r.foodReaction?.rawValue)
        assign(self, \.diaperType, r.diaperType?.rawValue)
        assign(self, \.peeAmount, r.peeAmount?.rawValue)
        assign(self, \.poopColor, r.poopColor?.rawValue)
        assign(self, \.poopConsistency, r.poopConsistency?.rawValue)
        assign(self, \.hasRash, r.hasRash)
        assign(self, \.weightKg, r.weightKg.map(NSNumber.init(value:)))
        assign(self, \.heightCm, r.heightCm.map(NSNumber.init(value:)))
        assign(self, \.headCm, r.headCm.map(NSNumber.init(value:)))
        assign(self, \.medicationName, r.medicationName?.nilIfBlank)
        assign(self, \.dosage, r.dosage?.nilIfBlank)
        assign(self, \.temperatureC, r.temperatureC.map(NSNumber.init(value:)))
        assign(self, \.symptoms, r.symptoms?.nilIfBlank)
        assign(self, \.vaccineName, r.vaccineName?.nilIfBlank)
        assign(self, \.activityType, r.activityType?.rawValue)
        assign(self, \.photoData, r.photoData)
    }
}

/// Sets a managed property only when the value actually changes. Assigning an
/// unchanged value still marks it dirty, and a dirty field wins the merge
/// against a newer value from another device (e.g. a stopped timer would start
/// again) and is uploaded to iCloud again (photos included).
private func assign<Object: NSManagedObject, Value: Equatable>(
    _ object: Object, _ keyPath: ReferenceWritableKeyPath<Object, Value>, _ value: Value
) {
    if object[keyPath: keyPath] != value { object[keyPath: keyPath] = value }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
