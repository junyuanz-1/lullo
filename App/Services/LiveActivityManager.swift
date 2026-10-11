import ActivityKit
import BabyCore
import Foundation
import OSLog

/// Mirrors running timers to Live Activities (Lock Screen and Dynamic Island).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private let logger = Logger(subsystem: "Lullo", category: "LiveActivity")
    /// Timers we already started an activity for, so one the user swiped away is not recreated.
    private let startedKey = "liveActivityStartedEventIDs"

    func sync(with snapshot: WidgetSnapshot) {
        let running: [UUID: (BabySnapshot, BabySnapshot.RunningTimer)] = Dictionary(
            snapshot.babies.flatMap { baby in baby.runningTimers.map { ($0.id, (baby, $0)) } },
            uniquingKeysWith: { first, _ in first }
        )

        for activity in Activity<TrackerActivityAttributes>.activities {
            if let entry = running[activity.attributes.eventID] {
                let state = TrackerActivityAttributes.ContentState(timer: entry.1)
                if activity.content.state != state {
                    Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
                }
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }

        guard AppSettings.liveActivitiesEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var started = Set(SharedContainer.defaults.stringArray(forKey: startedKey) ?? [])
        let existing = Set(Activity<TrackerActivityAttributes>.activities.map(\.attributes.eventID))

        for (id, (baby, timer)) in running where !existing.contains(id) && !started.contains(id.uuidString) {
            let attributes = TrackerActivityAttributes(
                eventID: id,
                babyID: baby.id,
                babyName: baby.name,
                kind: timer.kind,
                activityType: timer.activityType
            )
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: .init(timer: timer), staleDate: nil),
                    pushType: nil
                )
                started.insert(id.uuidString)
            } catch {
                // Usually means the app is in the background; we try again next time it is active.
                logger.debug("Could not start Live Activity: \(error.localizedDescription)")
            }
        }
        // Only remember timers that are still running.
        let stillRunning = started.filter { running.keys.map(\.uuidString).contains($0) }
        SharedContainer.defaults.set(Array(stillRunning), forKey: startedKey)
    }

    func endAll() {
        for activity in Activity<TrackerActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
