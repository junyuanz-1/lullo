import AppIntents
import BabyCore
import Foundation

// These intents are compiled into both the app and the widget extension. They
// conform to LiveActivityIntent, so the system always runs `perform()` in the
// app's process, even when a widget or Live Activity button triggers them.
// That keeps every database write (and CloudKit sync) in the app.

enum DiaperTypeOption: String, AppEnum {
    case wet, dirty, mixed, dry

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper"
    static var caseDisplayRepresentations: [DiaperTypeOption: DisplayRepresentation] = [
        .wet: "Wet",
        .dirty: "Dirty",
        .mixed: "Wet + Dirty",
        .dry: "Dry",
    ]

    var diaperType: DiaperType { DiaperType(rawValue: rawValue) ?? .wet }
}

enum BreastSideOption: String, AppEnum {
    case left, right

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Side"
    static var caseDisplayRepresentations: [BreastSideOption: DisplayRepresentation] = [
        .left: "Left",
        .right: "Right",
    ]

    var side: BreastSide { self == .left ? .left : .right }
}

struct StartSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Sleep"
    static var description = IntentDescription("Starts a sleep timer.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    init() {}
    init(babyID: UUID?) { self.babyID = babyID?.uuidString }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let name = await IntentActions.startSleep(babyID: babyID.flatMap(UUID.init(uuidString:)))
        let message = name.map { String(localized: "Sleep timer started for \($0).") }
            ?? String(localized: "Add a baby in the app first.")
        return .result(dialog: "\(message)")
        #endif
    }
}

struct WakeUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Baby Woke Up"
    static var description = IntentDescription("Stops the running sleep timer.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    init() {}
    init(babyID: UUID?) { self.babyID = babyID?.uuidString }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let slept = await IntentActions.wakeUp(babyID: babyID.flatMap(UUID.init(uuidString:)))
        let message = slept.map { String(localized: "Slept for \(Fmt.duration($0)).") }
            ?? String(localized: "No sleep timer is running.")
        return .result(dialog: "\(message)")
        #endif
    }
}

struct StartNursingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Nursing"
    static var description = IntentDescription("Starts a breastfeeding timer on the given side, or the suggested side.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    @Parameter(title: "Side")
    var side: BreastSideOption?

    init() {}
    init(babyID: UUID?, side: BreastSide?) {
        self.babyID = babyID?.uuidString
        self.side = side.map { $0 == .left ? .left : .right }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let started = await IntentActions.startNursing(babyID: babyID.flatMap(UUID.init(uuidString:)), side: side?.side)
        let message = started.map { String(localized: "Nursing timer started on the \($0.title) side.") }
            ?? String(localized: "Add a baby in the app first.")
        return .result(dialog: "\(message)")
        #endif
    }
}

struct FinishNursingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Nursing"
    static var description = IntentDescription("Stops the running breastfeeding timer.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    init() {}
    init(babyID: UUID?) { self.babyID = babyID?.uuidString }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let total = await IntentActions.finishNursing(babyID: babyID.flatMap(UUID.init(uuidString:)))
        let message = total.map { String(localized: "Nursed for \(Fmt.duration($0)).") }
            ?? String(localized: "No nursing timer is running.")
        return .result(dialog: "\(message)")
        #endif
    }
}

struct LogBottleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Bottle"
    static var description = IntentDescription("Logs a bottle feed now, in the units chosen in the app.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    @Parameter(title: "Amount", requestValueDialog: "How much did the baby drink?")
    var amount: Double

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let ml = AppSettings.unitSystem == .metric ? amount : UnitConversion.ml(fromOunces: amount)
        let ok = await IntentActions.logBottle(babyID: babyID.flatMap(UUID.init(uuidString:)), amountML: ml)
        let message = ok
            ? String(localized: "Logged a \(Fmt.volume(ml)) bottle.")
            : String(localized: "Add a baby in the app first.")
        return .result(dialog: "\(message)")
        #endif
    }
}

struct LogDiaperIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Diaper"
    static var description = IntentDescription("Logs a diaper change now.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    @Parameter(title: "Type", default: .wet)
    var type: DiaperTypeOption

    init() {}
    init(babyID: UUID?, type: DiaperType) {
        self.babyID = babyID?.uuidString
        self.type = DiaperTypeOption(rawValue: type.rawValue) ?? .wet
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let ok = await IntentActions.logDiaper(babyID: babyID.flatMap(UUID.init(uuidString:)), type: type.diaperType)
        let message = ok
            ? String(localized: "Logged a \(type.diaperType.title) diaper.")
            : String(localized: "Add a baby in the app first.")
        return .result(dialog: "\(message)")
        #endif
    }
}

struct LogFussyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Fussy"
    static var description = IntentDescription("Logs that the baby is fussy now. Add the details in the app later.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    init() {}
    init(babyID: UUID?) { self.babyID = babyID?.uuidString }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        if let readOnly = await IntentActions.readOnlyMessage(babyID: babyID.flatMap(UUID.init(uuidString:))) {
            return .result(dialog: "\(readOnly)")
        }
        let name = await IntentActions.logFussy(babyID: babyID.flatMap(UUID.init(uuidString:)))
        let message = name.map { String(localized: "Logged a fussy spell for \($0).") }
            ?? String(localized: "Add a baby in the app first.")
        return .result(dialog: "\(message)")
        #endif
    }
}

/// "Baby stopped crying": ends the fussy spell in progress, or, when none was
/// logged, asks how long ago it started and logs the whole spell.
struct FussyEndedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Baby Stopped Crying"
    static var description = IntentDescription("Ends the fussy spell in progress. If none was logged, asks how long ago it started and logs it.")

    @Parameter(title: "Baby ID")
    var babyID: String?

    @Parameter(title: "How Long Ago", defaultUnit: .minutes)
    var startedAgo: Measurement<UnitDuration>?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        let id = babyID.flatMap(UUID.init(uuidString:))
        if let readOnly = await IntentActions.readOnlyMessage(babyID: id) {
            return .result(dialog: "\(readOnly)")
        }
        let message: String
        switch await IntentActions.endFussy(babyID: id) {
        case .ended(let duration):
            message = String(localized: "Fussed for \(Fmt.duration(duration)).")
        case .noBaby:
            message = String(localized: "Add a baby in the app first.")
        case .noneOpen:
            // Nothing was logged when it started: ask when, and log the whole spell.
            guard let startedAgo else {
                let question: LocalizedStringResource = "How long ago did the fussing start?"
                throw $startedAgo.needsValueError(IntentDialog(question))
            }
            let seconds = startedAgo.converted(to: .seconds).value
            if seconds < 60 || seconds > 12 * 3600 {
                message = String(localized: "Say a time between 1 minute and 12 hours ago.")
            } else if await IntentActions.logEndedFussy(babyID: id, startedAgo: seconds) {
                message = String(localized: "Logged \(Fmt.duration(seconds)) of fussing.")
            } else {
                message = String(localized: "Add a baby in the app first.")
            }
        }
        return .result(dialog: "\(message)")
        #endif
    }
}

/// The widget's "Calm" button: ends the spell it showed.
struct EndFussyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Fussy Spell"
    static var isDiscoverable = false

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}
    init(eventID: UUID) { self.eventID = eventID.uuidString }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: eventID) { await IntentActions.endFussy(eventID: id) }
        #endif
        return .result()
    }
}

struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var isDiscoverable = false

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}
    init(eventID: UUID) { self.eventID = eventID.uuidString }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: eventID) { await IntentActions.stopTimer(eventID: id) }
        #endif
        return .result()
    }
}

struct SwitchNursingSideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Switch Side"
    static var isDiscoverable = false

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}
    init(eventID: UUID) { self.eventID = eventID.uuidString }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: eventID) { await IntentActions.switchNursingSide(eventID: id) }
        #endif
        return .result()
    }
}

struct ToggleNursingPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Nursing"
    static var isDiscoverable = false

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}
    init(eventID: UUID) { self.eventID = eventID.uuidString }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: eventID) { await IntentActions.toggleNursingPause(eventID: id) }
        #endif
        return .result()
    }
}
