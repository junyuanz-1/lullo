import ActivityKit
import BabyCore
import Foundation

/// Live Activity for a running timer (sleep, nursing, pumping or an activity).
struct TrackerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        // Nursing only
        var activeSide: BreastSide?
        var activeSideStartedAt: Date?
        var leftDuration: TimeInterval
        var rightDuration: TimeInterval

        var isNursingPaused: Bool { activeSide == nil }

        /// A start date such that a count-up timer from it shows the total nursing time.
        var nursingTimerStart: Date? {
            guard let since = activeSideStartedAt, activeSide != nil else { return nil }
            return since.addingTimeInterval(-(leftDuration + rightDuration))
        }

        func sideTimerStart(_ side: BreastSide) -> Date? {
            guard activeSide == side, let since = activeSideStartedAt else { return nil }
            return since.addingTimeInterval(-(side == .left ? leftDuration : rightDuration))
        }

        func storedDuration(_ side: BreastSide) -> TimeInterval {
            side == .left ? leftDuration : rightDuration
        }

        init(timer: BabySnapshot.RunningTimer) {
            startDate = timer.startDate
            activeSide = timer.activeSide
            activeSideStartedAt = timer.activeSideStartedAt
            leftDuration = timer.leftDuration
            rightDuration = timer.rightDuration
        }
    }

    var eventID: UUID
    var babyID: UUID
    var babyName: String
    var kind: EventKind
    var activityType: ActivityType?

    var title: String {
        if kind == .activity, let activityType { return activityType.title }
        return kind.title
    }
}
