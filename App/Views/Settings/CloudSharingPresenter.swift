import CloudKit
import CoreData
import UIKit

/// Presents Apple's standard sharing UI (invite people, see participants,
/// change permissions, stop sharing) for a baby.
///
/// UICloudSharingController is presented from UIKit directly because it does
/// not behave well inside a SwiftUI sheet.
@MainActor
enum CloudSharingPresenter {
    private static var activeDelegate: SharingDelegate?

    static func present(share: CKShare, baby: Baby, persistence: PersistenceController) {
        let delegate = SharingDelegate(baby: baby, persistence: persistence)
        activeDelegate = delegate
        let controller = UICloudSharingController(share: share, container: persistence.cloudKitContainer)
        controller.delegate = delegate
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        UIApplication.shared.topViewController?.present(controller, animated: true)
    }

    private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
        let baby: Baby
        let persistence: PersistenceController

        init(baby: Baby, persistence: PersistenceController) {
            self.baby = baby
            self.persistence = persistence
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            baby.displayName
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            baby.photoData
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share {
                persistence.persistUpdatedShare(share, for: baby)
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // A participant who leaves loses their local copy; the owner keeps the data.
            if persistence.isParticipant(baby), let share = csc.share {
                persistence.purgeLocalCopy(of: share)
            }
        }
    }
}
