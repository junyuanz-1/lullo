import AppIntents
import BabyCore
import Foundation

/// App-side implementations for the shared intents (see Shared/TrackerIntents.swift).
@MainActor
enum IntentActions {
    private static var store: TrackerStore { TrackerStore.shared }

    /// The baby a widget or Shortcut named, or the selected baby when none was
    /// named. A named baby that no longer exists gives nil rather than quietly
    /// logging to someone else.
    private static func baby(_ id: UUID?) -> Baby? {
        guard let id else { return store.selectedBaby }
        return store.baby(id: id)
    }

    /// A timer the Live Activity or widget still shows as running. Buttons on an
    /// out-of-date display (stopped or deleted on another phone) must not reopen
    /// or re-end it; refreshing makes the display catch up instead.
    private static func runningEvent(_ id: UUID, kind: EventKind? = nil) -> Event? {
        guard let event = store.event(id: id), event.record.isOngoing,
              kind.map({ event.eventKind == $0 }) ?? true else {
            store.refreshSideEffects()
            return nil
        }
        return event
    }

    /// Returns the baby's name, or nil when there is no baby.
    static func startSleep(babyID: UUID?) -> String? {
        guard let baby = baby(babyID), store.startTimer(.sleep, for: baby) != nil else { return nil }
        store.refreshSideEffects()
        return baby.displayName
    }

    /// Returns how long the baby slept, or nil when no sleep was running.
    static func wakeUp(babyID: UUID?) -> TimeInterval? {
        guard let baby = baby(babyID), let sleep = store.runningTimer(.sleep, for: baby) else { return nil }
        store.stopTimer(sleep)
        store.refreshSideEffects()
        return sleep.record.duration()
    }

    static func startNursing(babyID: UUID?, side: BreastSide?) -> BreastSide? {
        guard let baby = baby(babyID), let event = store.startNursing(for: baby, side: side) else { return nil }
        store.refreshSideEffects()
        return event.record.activeSide
    }

    /// Returns the total nursing time, or nil when no nursing timer was running.
    static func finishNursing(babyID: UUID?) -> TimeInterval? {
        guard let baby = baby(babyID), let session = store.runningTimer(.nursing, for: baby) else { return nil }
        store.stopTimer(session)
        store.refreshSideEffects()
        return session.record.duration()
    }

    static func logBottle(babyID: UUID?, amountML: Double) -> Bool {
        guard let baby = baby(babyID), let id = baby.id else { return false }
        let content = store.lastEvent(of: [.bottle], for: baby)?.record.bottleContent ?? .formula
        // A finished bottle: without an end it would read as a running bottle timer.
        let now = Date()
        let saved = store.save(EventRecord(babyID: id, kind: .bottle, startDate: now, endDate: now, amountML: amountML, bottleContent: content))
        store.refreshSideEffects()
        return saved != nil
    }

    static func logDiaper(babyID: UUID?, type: DiaperType) -> Bool {
        guard let baby = baby(babyID) else { return false }
        let saved = store.logDiaper(type, for: baby)
        store.refreshSideEffects()
        return saved != nil
    }

    static func stopTimer(eventID: UUID) {
        guard let event = runningEvent(eventID) else { return }
        store.stopTimer(event)
        store.refreshSideEffects()
    }

    static func switchNursingSide(eventID: UUID) {
        guard let event = runningEvent(eventID, kind: .nursing) else { return }
        store.switchNursingSide(event)
        store.refreshSideEffects()
    }

    static func toggleNursingPause(eventID: UUID) {
        guard let event = runningEvent(eventID, kind: .nursing) else { return }
        store.toggleNursingPause(event)
        store.refreshSideEffects()
    }
}

/// Siri and Shortcuts phrases.
struct TrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSleepIntent(),
            phrases: [
                "Start sleep in \(.applicationName)",
                "Baby is sleeping in \(.applicationName)",
            ],
            shortTitle: "Start Sleep",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: WakeUpIntent(),
            phrases: [
                "Baby woke up in \(.applicationName)",
                "Stop sleep in \(.applicationName)",
            ],
            shortTitle: "Baby Woke Up",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: StartNursingIntent(),
            phrases: [
                "Start nursing in \(.applicationName)",
                "Start breastfeeding in \(.applicationName)",
            ],
            shortTitle: "Start Nursing",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: FinishNursingIntent(),
            phrases: [
                "Finish nursing in \(.applicationName)",
                "Done breastfeeding in \(.applicationName)",
            ],
            shortTitle: "Finish Nursing",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Log a bottle in \(.applicationName)",
                "Baby had a bottle in \(.applicationName)",
            ],
            shortTitle: "Log Bottle",
            systemImageName: "waterbottle.fill"
        )
        AppShortcut(
            intent: LogDiaperIntent(),
            phrases: [
                "Log a diaper in \(.applicationName)",
                "Log a \(\.$type) diaper in \(.applicationName)",
            ],
            shortTitle: "Log Diaper",
            systemImageName: "leaf.fill"
        )
    }
}
