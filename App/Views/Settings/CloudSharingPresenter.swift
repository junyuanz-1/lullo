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
        let delegate = SharingDelegate(share: share, baby: baby, persistence: persistence)
        activeDelegate = delegate
        let controller = UICloudSharingController(share: share, container: persistence.cloudKitContainer)
        controller.delegate = delegate
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        UIApplication.shared.topViewController?.present(controller, animated: true)
    }

    private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
        /// The share as presented: after Stop Sharing `csc.share` can be nil.
        let share: CKShare
        let baby: Baby
        let persistence: PersistenceController

        init(share: CKShare, baby: Baby, persistence: PersistenceController) {
            self.share = share
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
            sharingChanged()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            let share = csc.share ?? self.share
            // A participant who leaves loses their local copy; the owner keeps the data.
            if persistence.isParticipant(baby) {
                persistence.purgeLocalCopy(of: share)
            } else {
                persistence.shareStopped(share)
            }
            sharingChanged()
        }

        /// Whether a baby is shared is read from the container, which SwiftUI
        /// can't observe: redraw what shows it (the Shared badge, Settings).
        private func sharingChanged() {
            TrackerStore.shared.objectWillChange.send()
        }
    }
}
