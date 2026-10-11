import CoreData
import XCTest
@testable import InfantTracker

/// Guards against changes that would break CloudKit sync or translations.
final class ConfigurationTests: XCTestCase {
    func testModelIsCloudKitCompatible() {
        for entity in ManagedModel.shared.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") must not use unique constraints")
            for (name, attribute) in entity.attributesByName {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name ?? "?").\(name) must be optional or have a default value"
                )
            }
            for (name, relationship) in entity.relationshipsByName {
                XCTAssertTrue(relationship.isOptional, "\(entity.name ?? "?").\(name) must be optional")
                XCTAssertNotNil(relationship.inverseRelationship, "\(entity.name ?? "?").\(name) needs an inverse")
                XCTAssertNotEqual(relationship.deleteRule, .denyDeleteRule)
            }
        }
    }

    func testManagedObjectClassesResolve() {
        let context = PersistenceController(inMemory: true).viewContext
        XCTAssertTrue(NSEntityDescription.insertNewObject(forEntityName: "Baby", into: context) is Baby)
        XCTAssertTrue(NSEntityDescription.insertNewObject(forEntityName: "Event", into: context) is Event)
    }

    func testChineseTranslationsAreComplete() throws {
        let english = try strings(for: "en")
        let chinese = try strings(for: "zh-Hans")
        XCTAssertFalse(english.isEmpty)
        for (key, _) in english {
            let translated = try XCTUnwrap(chinese[key], "Missing zh-Hans translation for \"\(key)\"")
            XCTAssertEqual(
                key.components(separatedBy: "%@").count,
                translated.components(separatedBy: "%@").count,
                "Placeholder count differs for \"\(key)\""
            )
        }
    }

    private func strings(for localization: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization),
            "No Localizable.strings for \(localization)"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }
}
