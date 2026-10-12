import CoreData
import XCTest
@testable import Tinytide

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

    func testTranslationsAreComplete() throws {
        let english = try strings(for: "en")
        XCTAssertFalse(english.isEmpty)
        let localizations = Bundle.main.localizations.filter { $0 != "en" && $0 != "Base" }
        XCTAssertGreaterThanOrEqual(localizations.count, 8, "Expected all shipped languages, found \(localizations)")
        for localization in localizations {
            let translated = try strings(for: localization)
            for (key, _) in english {
                let value = try XCTUnwrap(translated[key], "Missing \(localization) translation for \"\(key)\"")
                XCTAssertEqual(placeholderCount(key), placeholderCount(value), "Placeholder count differs for \"\(key)\" in \(localization)")
            }
        }
    }

    private func placeholderCount(_ string: String) -> Int {
        string.matches(of: #/%(\d+\$)?@/#).count
    }

    private func strings(for localization: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization),
            "No Localizable.strings for \(localization)"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }
}
