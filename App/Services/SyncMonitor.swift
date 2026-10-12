import CloudKit
import Combine
import CoreData
import Foundation

/// Publishes iCloud account and sync status for the Settings screen.
@MainActor
final class SyncMonitor: ObservableObject {
    enum AccountState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
    }

    @Published private(set) var account: AccountState = .unknown
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private var cancellables: Set<AnyCancellable> = []
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification, object: persistence.container)
            .compactMap { $0.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Another account's data will be downloaded from scratch.
                AppSettings.initialCloudImportDone = false
                AppSettings.firstCloudImportWaitStart = nil
                Task { await self?.refreshAccount() }
            }
            .store(in: &cancellables)
    }

    func refreshAccount() async {
        guard !persistence.inMemory else { return }
        do {
            switch try await persistence.cloudKitContainer.accountStatus() {
            case .available: account = .available
            case .noAccount: account = .noAccount
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            case .couldNotDetermine: account = .unknown
            @unknown default: account = .unknown
            }
        } catch {
            account = .unknown
        }
        AppSettings.cloudAccountAvailable = account == .available
        if account == .available, !AppSettings.initialCloudImportDone, AppSettings.firstCloudImportWaitStart == nil {
            AppSettings.firstCloudImportWaitStart = Date()
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            isSyncing = true
            return
        }
        isSyncing = false
        if event.succeeded {
            if event.type != .setup { lastSync = event.endDate }
            // The private store's import is the user's own data; the shared
            // store's (often empty and quick) doesn't mean that has arrived.
            if event.type == .import, event.storeIdentifier == persistence.privateStore?.identifier {
                AppSettings.initialCloudImportDone = true
            }
            lastError = nil
        } else if let error = event.error {
            lastError = error.localizedDescription
        }
    }
}
