import AppIntents
import BabyCore
import Foundation

/// App-side implementations for the shared intents (see Shared/TrackerIntents.swift).
@MainActor
enum IntentActions {
    private static var store: TrackerStore { TrackerStore.shared }

    private static func baby(_ id: UUID?) -> Baby? {
        store.baby(id: id) ?? store.selectedBaby
    }

    /// Returns the baby's name, or nil when there is no baby.
    static func startSleep(babyID: UUID?) -> String? {
        guard let baby = baby(babyID) else { return nil }
        store.startTimer(.sleep, for: baby)
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

    static func logDiaper(babyID: UUID?, type: DiaperType) -> Bool {
        guard let baby = baby(babyID) else { return false }
        store.logDiaper(type, for: baby)
        store.refreshSideEffects()
        return true
    }

    static func stopTimer(eventID: UUID) {
        guard let event = store.event(id: eventID) else { return }
        store.stopTimer(event)
        store.refreshSideEffects()
    }

    static func switchNursingSide(eventID: UUID) {
        guard let event = store.event(id: eventID) else { return }
        store.switchNursingSide(event)
        store.refreshSideEffects()
    }

    static func toggleNursingPause(eventID: UUID) {
        guard let event = store.event(id: eventID) else { return }
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
