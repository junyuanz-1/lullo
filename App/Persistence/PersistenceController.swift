import BabyCore
import CloudKit
import CoreData
import OSLog

/// Owns the Core Data stack.
///
/// Two stores are mirrored to iCloud:
/// - `private.sqlite`: babies you created, in your private CloudKit database.
/// - `shared.sqlite`: babies other people shared with you, in the shared database.
///
/// Sharing a baby moves its record (and its events) into a CloudKit share zone
/// that invited caregivers can read and write.
final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer
    let inMemory: Bool
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private(set) var loadError: Error?

    private let logger = Logger(subsystem: "InfantTracker", category: "Persistence")

    var viewContext: NSManagedObjectContext { container.viewContext }

    var cloudKitContainer: CKContainer { CKContainer(identifier: SharedContainer.cloudKitContainerID) }

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        container = NSPersistentCloudKitContainer(name: "InfantTracker", managedObjectModel: ManagedModel.shared)

        let privateDescription: NSPersistentStoreDescription
        let sharedDescription: NSPersistentStoreDescription
        if inMemory {
            privateDescription = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null/private"))
            sharedDescription = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null/shared"))
            privateDescription.type = NSInMemoryStoreType
            sharedDescription.type = NSInMemoryStoreType
        } else {
            let directory = SharedContainer.directory.appendingPathComponent("Stores", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            privateDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent("private.sqlite"))
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: SharedContainer.cloudKitContainerID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            sharedDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent("shared.sqlite"))
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: SharedContainer.cloudKitContainerID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
        }
        for description in [privateDescription, sharedDescription] {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        let privateURL = privateDescription.url
        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error {
                self.logger.error("Failed to load store \(description.url?.lastPathComponent ?? "?"): \(error.localizedDescription)")
                self.loadError = error
                return
            }
            guard let url = description.url,
                  let store = self.container.persistentStoreCoordinator.persistentStore(for: url) else { return }
            if url == privateURL {
                self.privateStore = store
            } else {
                self.sharedStore = store
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"

        #if DEBUG
        // Run once with this launch argument before deploying the CloudKit schema to production.
        if !inMemory, ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
            do {
                try container.initializeCloudKitSchema(options: [])
            } catch {
                logger.error("initializeCloudKitSchema failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - Creating objects in the right store

    func newBaby(in context: NSManagedObjectContext) -> Baby {
        let baby = Baby(context: context)
        if let privateStore { context.assign(baby, to: privateStore) }
        return baby
    }

    /// Events must live in the same store as their baby (private, or shared if
    /// the baby was shared with us).
    func newEvent(for baby: Baby, in context: NSManagedObjectContext) -> Event {
        let event = Event(context: context)
        if let store = baby.objectID.persistentStore ?? privateStore {
            context.assign(event, to: store)
        }
        event.baby = baby
        return event
    }

    // MARK: - Sharing

    /// True when someone else owns this baby and shared it with us.
    func isParticipant(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }

    func existingShare(for object: NSManagedObject) -> CKShare? {
        if let share = try? container.fetchShares(matching: [object.objectID])[object.objectID] {
            return share
        }
        return nil
    }

    func isShared(_ object: NSManagedObject) -> Bool {
        isParticipant(object) || existingShare(for: object) != nil
    }

    func canEdit(_ object: NSManagedObject) -> Bool {
        if inMemory { return true }
        return container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    /// Returns the baby's existing share, or creates one.
    func share(_ baby: Baby) async throws -> CKShare {
        if let share = existingShare(for: baby) { return share }
        let (_, share, _) = try await container.share([baby], to: nil)
        share[CKShare.SystemFieldKey.title] = baby.displayName as CKRecordValue
        share.publicPermission = .none
        return share
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [logger] _, error in
            if let error { logger.error("Accepting share failed: \(error.localizedDescription)") }
        }
    }

    func persistUpdatedShare(_ share: CKShare, for object: NSManagedObject) {
        guard let store = object.objectID.persistentStore else { return }
        container.persistUpdatedShare(share, in: store) { [logger] _, error in
            if let error { logger.error("Persisting share failed: \(error.localizedDescription)") }
        }
    }

    /// Called after a participant leaves a share: removes the local copy.
    func purgeLocalCopy(of share: CKShare) {
        guard let sharedStore else { return }
        container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore) { [logger] _, error in
            if let error { logger.error("Purging share zone failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Saving

    func save(_ context: NSManagedObjectContext? = nil) {
        let context = context ?? viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
            context.rollback()
        }
    }
}
