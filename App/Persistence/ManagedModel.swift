import CoreData

/// The Core Data model, built in code so it is easy to review and diff.
///
/// CloudKit mirroring rules this model follows: every attribute is optional or
/// has a default, there are no unique constraints, and every relationship is
/// optional with an inverse.
enum ManagedModel {
    static let shared: NSManagedObjectModel = make()

    private static func make() -> NSManagedObjectModel {
        let baby = NSEntityDescription()
        baby.name = "Baby"
        baby.managedObjectClassName = "Baby"
        baby.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("birthDate", .dateAttributeType),
            attribute("sex", .stringAttributeType),
            attribute("photoData", .binaryDataAttributeType, externalStorage: true),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ]

        let event = NSEntityDescription()
        event.name = "Event"
        event.managedObjectClassName = "Event"
        event.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("kind", .stringAttributeType),
            attribute("startDate", .dateAttributeType),
            attribute("endDate", .dateAttributeType),
            attribute("note", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("authorName", .stringAttributeType),
            attribute("sleepLocation", .stringAttributeType),
            attribute("leftDuration", .doubleAttributeType, defaultValue: 0.0),
            attribute("rightDuration", .doubleAttributeType, defaultValue: 0.0),
            attribute("activeSide", .stringAttributeType),
            attribute("activeSideStartedAt", .dateAttributeType),
            attribute("lastSide", .stringAttributeType),
            attribute("amountML", .doubleAttributeType),
            attribute("leftAmountML", .doubleAttributeType),
            attribute("rightAmountML", .doubleAttributeType),
            attribute("bottleContent", .stringAttributeType),
            attribute("foodName", .stringAttributeType),
            attribute("foodReaction", .stringAttributeType),
            attribute("diaperType", .stringAttributeType),
            attribute("poopColor", .stringAttributeType),
            attribute("poopConsistency", .stringAttributeType),
            attribute("peeAmount", .stringAttributeType),
            attribute("hasRash", .booleanAttributeType, defaultValue: false),
            attribute("weightKg", .doubleAttributeType),
            attribute("heightCm", .doubleAttributeType),
            attribute("headCm", .doubleAttributeType),
            attribute("medicationName", .stringAttributeType),
            attribute("dosage", .stringAttributeType),
            attribute("temperatureC", .doubleAttributeType),
            attribute("symptoms", .stringAttributeType),
            attribute("vaccineName", .stringAttributeType),
            attribute("activityType", .stringAttributeType),
            attribute("fussIntensity", .stringAttributeType),
            // Multiple choices as comma-separated raw values (see EventRecord.joinedRawValues).
            attribute("fussCauses", .stringAttributeType),
            attribute("soothingMethods", .stringAttributeType),
            attribute("photoData", .binaryDataAttributeType, externalStorage: true),
        ]

        let events = NSRelationshipDescription()
        events.name = "events"
        events.destinationEntity = event
        events.minCount = 0
        events.maxCount = 0 // to-many
        events.deleteRule = .cascadeDeleteRule
        events.isOptional = true

        let eventBaby = NSRelationshipDescription()
        eventBaby.name = "baby"
        eventBaby.destinationEntity = baby
        eventBaby.minCount = 0
        eventBaby.maxCount = 1
        eventBaby.deleteRule = .nullifyDeleteRule
        eventBaby.isOptional = true

        events.inverseRelationship = eventBaby
        eventBaby.inverseRelationship = events

        baby.properties.append(events)
        event.properties.append(eventBaby)

        if let start = event.propertiesByName["startDate"], let kind = event.propertiesByName["kind"] {
            event.indexes = [
                NSFetchIndexDescription(name: "byStartDate", elements: [
                    NSFetchIndexElementDescription(property: start, collationType: .binary),
                ]),
                NSFetchIndexDescription(name: "byKindAndStart", elements: [
                    NSFetchIndexElementDescription(property: kind, collationType: .binary),
                    NSFetchIndexElementDescription(property: start, collationType: .binary),
                ]),
            ]
        }

        let model = NSManagedObjectModel()
        model.entities = [baby, event]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        defaultValue: Any? = nil,
        externalStorage: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = defaultValue
        attribute.allowsExternalBinaryDataStorage = externalStorage
        return attribute
    }
}
