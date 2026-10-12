import BabyCore
import Foundation
import UserNotifications

/// Local reminders: feed / diaper intervals, the nap "sweet spot", and medication doses.
enum NotificationManager {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Recomputes interval reminders from the latest snapshot.
    static func reschedule(from snapshot: WidgetSnapshot, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        let defaults = AppSettings.defaults
        let feedOn = defaults.bool(forKey: SettingsKey.feedReminderEnabled)
        let feedHours = defaults.object(forKey: SettingsKey.feedReminderHours) as? Double ?? 3
        let diaperOn = defaults.bool(forKey: SettingsKey.diaperReminderEnabled)
        let diaperHours = defaults.object(forKey: SettingsKey.diaperReminderHours) as? Double ?? 3
        let napOn = defaults.bool(forKey: SettingsKey.napReminderEnabled)

        center.getPendingNotificationRequests { pending in
            let managed = pending.map(\.identifier).filter {
                $0.hasPrefix("feed-") || $0.hasPrefix("diaper-") || $0.hasPrefix("nap-")
            }
            center.removePendingNotificationRequests(withIdentifiers: managed)

            for baby in snapshot.babies {
                if feedOn, let last = baby.lastFeed {
                    schedule(
                        id: "feed-\(baby.id.uuidString)",
                        title: String(localized: "Time to feed \(baby.name)?"),
                        body: String(localized: "Last feed was at \(Fmt.time(last.date))."),
                        at: last.date.addingTimeInterval(feedHours * 3600),
                        now: now
                    )
                }
                if diaperOn, let last = baby.lastDiaper {
                    schedule(
                        id: "diaper-\(baby.id.uuidString)",
                        title: String(localized: "Diaper check for \(baby.name)"),
                        body: String(localized: "Last change was at \(Fmt.time(last.date))."),
                        at: last.date.addingTimeInterval(diaperHours * 3600),
                        now: now
                    )
                }
                if napOn, let nap = baby.nextNap, baby.runningSleep == nil {
                    schedule(
                        id: "nap-\(baby.id.uuidString)",
                        title: nap.isBedtime
                            ? String(localized: "Bedtime is coming up for \(baby.name)")
                            : String(localized: "Nap time is coming up for \(baby.name)"),
                        body: String(localized: "Sweet spot: \(Fmt.time(nap.earliest)) – \(Fmt.time(nap.latest))"),
                        at: nap.earliest.addingTimeInterval(-10 * 60),
                        now: now
                    )
                }
            }
        }
    }

    static func scheduleMedicationReminder(eventID: UUID, babyName: String, medication: String, at date: Date) {
        schedule(
            id: "med-\(eventID.uuidString)",
            title: String(localized: "Medication for \(babyName)"),
            body: String(localized: "Next dose of \(medication) is due."),
            at: date,
            now: Date()
        )
    }

    static func cancelMedicationReminder(eventID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["med-\(eventID.uuidString)"])
    }

    /// Entries that have a pending medication reminder.
    static func pendingMedicationReminderEventIDs() async -> [UUID] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix("med-") else { return nil }
            return UUID(uuidString: String(request.identifier.dropFirst(4)))
        }
    }

    /// Moves a pending medication reminder by `delta` after the dose's time was
    /// edited, so "next dose in 4 h" still counts from the dose.
    static func shiftMedicationReminder(eventID: UUID, by delta: TimeInterval) async {
        let id = "med-\(eventID.uuidString)"
        let center = UNUserNotificationCenter.current()
        guard delta != 0,
              let request = await center.pendingNotificationRequests().first(where: { $0.identifier == id }),
              let fireDate = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        schedule(id: id, title: request.content.title, body: request.content.body, at: fireDate.addingTimeInterval(delta), now: Date())
    }

    private static func schedule(id: String, title: String, body: String, at date: Date, now: Date) {
        let interval = date.timeIntervalSince(now)
        guard interval > 5 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
