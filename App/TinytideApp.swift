import CloudKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct TinytideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TrackerStore.shared
    @StateObject private var syncMonitor = SyncMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if DemoMode.isEnabled { DemoMode.start() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, store.persistence.viewContext)
                .environmentObject(store)
                .environmentObject(syncMonitor)
                .task { await syncMonitor.refreshAccount() }
                .task {
                    TipJar.shared.startListening()
                    await Supporter.shared.refresh()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Demo mode is a still life: no widgets, Live Activities or backups.
            guard phase == .active, !DemoMode.isEnabled else { return }
            store.appBecameActive()
            Task {
                // Give iCloud a moment to bring in changes before the daily snapshot.
                try? await Task.sleep(for: .seconds(10))
                AutoBackup.shared.backUpIfDue(store: store)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKit pushes changes silently; this lets the app receive them.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Receives CloudKit share invitations ("Join" links sent by another caregiver).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            PersistenceController.shared.acceptShare(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        PersistenceController.shared.acceptShare(cloudKitShareMetadata)
    }
}
