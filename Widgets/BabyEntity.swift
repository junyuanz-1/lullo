import AppIntents
import BabyCore
import Foundation
import WidgetKit

/// A baby the user can pick when configuring a widget.
struct BabyEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Baby"
    static var defaultQuery = BabyEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BabyEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BabyEntity] {
        allBabies().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BabyEntity] {
        allBabies()
    }

    func defaultResult() async -> BabyEntity? {
        let snapshot = SharedContainer.loadSnapshot()
        return snapshot.baby(nil).map { BabyEntity(id: $0.id.uuidString, name: $0.name) }
    }

    private func allBabies() -> [BabyEntity] {
        SharedContainer.loadSnapshot().babies.map { BabyEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct SelectBabyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Baby"
    static var description = IntentDescription("Choose which baby this widget shows.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?
}
