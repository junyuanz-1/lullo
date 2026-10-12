import BabyCore
import CoreData
import SwiftUI
import TipKit
import UIKit

/// Identifies what the entry editor sheet should show.
struct EditorRoute: Identifiable {
    let id = UUID()
    var kind: EventKind
    var existing: Event?
    /// Forces the editor into timer or "log past" mode; nil picks the default.
    var mode: EventEditorView.Mode?
    /// Related kinds the new entry can switch between (the Health tile:
    /// medication, temperature, symptom, vaccine).
    var choices: [EventKind] = []
}

/// The entry editor in a sheet, sized to the kind of entry.
struct EditorSheet: View {
    @ObservedObject var baby: Baby
    let route: EditorRoute

    var body: some View {
        NavigationStack {
            EventEditorView(baby: baby, kind: route.kind, existing: route.existing, mode: route.mode, choices: route.choices)
        }
        // Short forms (diaper, note) open half-height so the Save button is close
        // at hand; drag up for more room.
        .presentationDetents(route.kind.prefersCompactSheet ? [.medium, .large] : [.large])
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject var baby: Baby
    @FetchRequest private var recent: FetchedResults<Event>
    @State private var editor: EditorRoute?
    @State private var toast: UndoToast?

    init(baby: Baby) {
        self.baby = baby
        _editor = State(initialValue: DemoMode.initialEditor.map { EditorRoute(kind: $0) })
        let since = Calendar.current.date(byAdding: .day, value: -3, to: Calendar.current.startOfDay(for: AppClock.now))!
        _recent = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
            // Recent entries, plus any timer still running from before the window.
            predicate: NSPredicate(
                format: "baby == %@ AND (startDate >= %@ OR (endDate == nil AND kind IN %@))",
                baby, since as NSDate, EventKind.allCases.filter(\.supportsTimer).map(\.rawValue)
            ),
            animation: .default
        )
    }

    private var records: [EventRecord] { recent.map(\.record) }
    private var running: [Event] { recent.filter { $0.record.isOngoing }.sorted { ($0.startDate ?? .now) < ($1.startDate ?? .now) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BabyHeader(baby: baby)

                    ForEach(running) { event in
                        TimerCard(event: event, onEdit: { editor = EditorRoute(kind: event.eventKind, existing: event) }, onStop: { stop(event) }, canEdit: canEdit)
                    }
                    if !running.isEmpty && AppSettings.liveActivitiesEnabled {
                        TipView(TinytideTips.lockScreen)
                    }

                    // What a tired parent checks first: how long since the last feed,
                    // diaper and sleep. The one-tap buttons come right after.
                    ClockTimeline(every: 30) { now in
                        StatusCards(records: records, now: now)
                    }

                    QuickActionsGrid(
                        records: records,
                        running: running,
                        editor: $editor,
                        startTimer: startTimer,
                        startNursing: startNursing,
                        stop: stop
                    )
                    // Read-only caregivers can look at entries (from Recent and the
                    // timer card) but not log new ones.
                    .disabled(!canEdit)

                    ClockTimeline(every: 30) { now in
                        VStack(spacing: 16) {
                            SweetSpotCard(baby: baby.record, records: records, now: now)
                            TodayCard(records: records, now: now)
                        }
                    }

                    if !store.persistence.isShared(baby) {
                        TipView(TinytideTips.invite)
                    }

                    RecentCard(
                        events: Array(recent.prefix(6)),
                        onSelect: { event in editor = EditorRoute(kind: event.eventKind, existing: event) },
                        onDelete: canEdit ? delete : nil
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .undoToast($toast)
            .toolbar {
                ToolbarItem(placement: .principal) { BabySwitcher(baby: baby) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { route in
                EditorSheet(baby: baby, route: route)
            }
        }
    }

    private var canEdit: Bool { store.canEdit(baby) }

    // MARK: One-tap actions

    private func startTimer(_ kind: EventKind, activityType: ActivityType?) {
        // Already running (say, started on another phone a moment ago and just
        // synced): the store hands back that timer, which is not ours to undo.
        if kind != .activity, store.runningTimer(kind, for: baby) != nil { return }
        guard let event = store.startTimer(kind, for: baby, activityType: activityType) else { return }
        haptic()
        TinytideTips.logged()
        let message: String
        switch kind {
        case .sleep: message = String(localized: "Sleep started")
        case .bottle: message = String(localized: "Bottle started")
        case .pumping: message = String(localized: "Pumping started")
        case .activity: message = String(localized: "\((activityType ?? .play).title) started")
        default: message = String(localized: "Timer started")
        }
        let version = event.updatedAt
        show(message) { undoStart(event, startedVersion: version) }
    }

    /// Takes back a timer just started from Today, unless it has been changed
    /// (or deleted) since, in which case Undo leaves it alone.
    private func undoStart(_ event: Event, startedVersion: Date?) {
        guard !event.isDeleted, event.managedObjectContext != nil, event.updatedAt == startedVersion else { return }
        store.delete(event)
    }

    private func startNursing(_ side: BreastSide?) {
        // A running session would only switch sides; the timer card does that.
        if store.runningTimer(.nursing, for: baby) != nil { return }
        guard let event = store.startNursing(for: baby, side: side) else { return }
        haptic()
        TinytideTips.logged()
        let chosen = event.record.activeSide ?? side ?? .left
        let version = event.updatedAt
        show(String(localized: "Nursing started · \(chosen.title)")) { undoStart(event, startedVersion: version) }
    }

    private func stop(_ event: Event) {
        let before = event.record
        store.stopTimer(event)
        haptic()
        let message: String
        switch before.kind {
        case .sleep: message = String(localized: "Sleep ended")
        case .nursing: message = String(localized: "Nursing finished")
        case .bottle: message = String(localized: "Bottle finished")
        case .pumping: message = String(localized: "Pumping finished")
        case .activity: message = String(localized: "Activity finished")
        default: message = String(localized: "Timer stopped")
        }
        // Stopping clears the timer's alarm; Undo puts the timer and its alarm
        // back exactly as they were.
        let alarm = TimerAlarms.shared.duration(for: before.id)
        let stoppedVersion = event.updatedAt
        var toast = UndoToast(message: message) {
            // Only if the entry is still exactly as the stop left it: an edit or a
            // delete made since (here or on another phone) wins over the Undo.
            guard let current = store.event(id: before.id), current.updatedAt == stoppedVersion else { return }
            store.save(before)
            if let alarm { TimerAlarms.shared.setDuration(alarm, for: before.id) }
        }
        if before.kind == .pumping || before.kind == .bottle {
            // Amounts are often known only at the end; offer the entry without
            // forcing it open.
            toast.action = (title: String(localized: "Add Amount"), perform: { editor = EditorRoute(kind: before.kind, existing: event) })
        }
        self.toast = toast
    }

    private func delete(_ event: Event) {
        let record = event.record
        let alarm = TimerAlarms.shared.duration(for: record.id)
        store.delete(event)
        haptic()
        show(String(localized: "Entry deleted")) {
            store.save(record)
            if let alarm, record.isOngoing { TimerAlarms.shared.setDuration(alarm, for: record.id) }
        }
    }

    private func show(_ message: String, undo: @escaping () -> Void) {
        toast = UndoToast(message: message, undo: undo)
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

struct BabyHeader: View {
    @EnvironmentObject private var store: TrackerStore
    @StateObject private var supporter = Supporter.shared
    @ObservedObject var baby: Baby

    var body: some View {
        HStack(spacing: 14) {
            BabyAvatar(photoData: baby.photoData, name: baby.displayName, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(baby.displayName).font(.title2.bold())
                Text(Fmt.age(birthDate: baby.birthDate ?? AppClock.now)).foregroundStyle(.secondary)
            }
            Spacer()
            if supporter.isSupporter {
                Image(systemName: "heart.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                    .accessibilityLabel(Text("Tinytide Supporter"))
            }
            if store.persistence.isShared(baby) {
                Label("Shared", systemImage: "person.2.fill")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Running timers

struct TimerCard: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject private var alarms = TimerAlarms.shared
    @ObservedObject var event: Event
    @Environment(\.dynamicTypeSize) private var typeSize
    var onEdit: () -> Void
    var onStop: () -> Void
    /// False for a read-only caregiver: the card shows the timer but its
    /// controls are disabled (the pencil still opens the entry to look at).
    var canEdit = true

    var body: some View {
        let record = event.record
        Card {
            // At accessibility text sizes the bell and pencil get their own row, so
            // the title isn't squeezed into hyphenated fragments.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    titleBlock(record)
                    HStack(spacing: 16) {
                        Spacer()
                        controls(record)
                    }
                }
            } else {
                HStack {
                    titleBlock(record)
                    Spacer()
                    controls(record)
                }
            }

            ClockTimeline(every: 1) { now in
                Group {
                    if record.kind == .nursing {
                        NursingControls(event: event, record: record, now: now, onStop: onStop)
                    } else {
                        HStack {
                            Text(Fmt.clock(record.duration(at: now)))
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Spacer()
                            Button(action: onStop) {
                                Label(record.kind == .sleep ? String(localized: "Wake Up") : String(localized: "Stop"), systemImage: "stop.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(record.kind.color)
                        }
                    }
                }
                .disabled(!canEdit)
            }
        }
    }
}

extension TimerCard {
    fileprivate func titleBlock(_ record: EventRecord) -> some View {
        HStack {
            KindIcon(systemImage: record.displayImage, color: record.kind.color)
            VStack(alignment: .leading) {
                Text(record.kind == .sleep ? String(localized: "Sleeping") : record.displayTitle).font(.headline)
                Text("Started \(Fmt.time(record.startDate))").font(.caption).foregroundStyle(.secondary)
                if let ring = alarms.fireDate(for: record) {
                    Label(String(localized: "Rings at \(Fmt.time(ring))"), systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(record.kind.color)
                }
            }
        }
    }

    @ViewBuilder
    fileprivate func controls(_ record: EventRecord) -> some View {
        if TimerAlarm.supportedKinds.contains(record.kind) {
            alarmMenu(for: record).disabled(!canEdit)
        }
        Button(action: onEdit) { Image(systemName: "pencil.circle.fill").font(.title2) }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit"))
    }

    /// Countdown for this timer, set right on the card: Off or one of the presets.
    fileprivate func alarmMenu(for record: EventRecord) -> some View {
        let current = alarms.duration(for: record.id).map { Int($0 / 60) }
        return Menu {
            Section(record.kind == .nursing ? String(localized: "Alarm per Side") : String(localized: "Alarm")) {
                Button {
                    setAlarm(nil, for: record)
                } label: {
                    if current == nil {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
                ForEach(TimerAlarm.presetMinutes(for: record.kind), id: \.self) { minutes in
                    Button {
                        setAlarm(TimeInterval(minutes * 60), for: record)
                    } label: {
                        let title = Fmt.duration(TimeInterval(minutes * 60), style: .short)
                        if current == minutes {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: current == nil ? "bell" : "bell.fill").font(.title2)
        }
        .accessibilityLabel(Text("Alarm"))
    }

    private func setAlarm(_ duration: TimeInterval?, for record: EventRecord) {
        alarms.setDuration(duration, for: record.id)
        alarms.rememberLastUsed(duration, for: record.kind)
    }
}

struct NursingControls: View {
    @EnvironmentObject private var store: TrackerStore
    var event: Event
    var record: EventRecord
    var now: Date
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(Fmt.clock(record.nursingTotal(at: now)))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 20) {
                ForEach([BreastSide.left, .right], id: \.self) { side in
                    let active = record.activeSide == side
                    Button {
                        store.setNursingSide(side, on: event)
                    } label: {
                        VStack(spacing: 4) {
                            Text(side.title).font(.headline)
                            Text(Fmt.clock(record.nursingElapsed(side, at: now))).monospacedDigit()
                            Image(systemName: active ? "pause.fill" : "play.fill")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(active ? Color.pink : Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(active ? .white : .pink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(active ? String(localized: "Pause \(side.title)") : String(localized: "Start \(side.title)"))
                }
            }
            HStack {
                if record.isNursingPaused {
                    Text("Paused").foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onStop) {
                    Label("Done", systemImage: "checkmark")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
        }
    }
}

// MARK: - Quick actions

/// The buttons under the status cards, in two groups so what a tap does is
/// predictable:
/// - Timers (sleep, nursing, pumping) start on a single tap and stop on the
///   next one. A ▶ badge marks them; while running the tile is outlined and
///   counts up. Long-press for "Start with Details" or to pick a side.
/// - Add Entry tiles always open a form (prefilled, so most entries are just
///   Save). A ＋ badge marks them.
/// Entries from earlier are one tap away under "Log Past" in the header.
struct QuickActionsGrid: View {
    /// Recent entries, newest first; used for the suggested nursing side.
    var records: [EventRecord]
    /// Running timers, oldest first.
    var running: [Event]
    @Binding var editor: EditorRoute?
    var startTimer: (EventKind, ActivityType?) -> Void
    var startNursing: (BreastSide?) -> Void
    var stop: (Event) -> Void

    static let timerKinds: [EventKind] = [.sleep, .nursing, .pumping]
    static let healthKinds: [EventKind] = [.medication, .temperature, .symptom, .vaccine]

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Four entry tiles a row, two at accessibility text sizes so titles fit.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 76), spacing: 12)]
    }

    /// The three timers side by side, or two a row at accessibility text sizes.
    private var timerColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    private func runningTimers(of kind: EventKind) -> [Event] { running.filter { $0.eventKind == kind } }

    private var suggestedSide: BreastSide {
        EventRecord.suggestedNextSide(after: records.first { $0.kind == .nursing })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The hint gets its own line so long translations don't crowd Log Past.
            VStack(alignment: .leading, spacing: 0) {
                // Log Past moves under the title when both don't fit on one line
                // (large text sizes), instead of squeezing "Timers" apart.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) {
                        groupTitle(String(localized: "Timers"))
                        Spacer(minLength: 8)
                        logPastMenu
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        groupTitle(String(localized: "Timers"))
                        logPastMenu
                    }
                }
                Text("Tap to start or stop").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: timerColumns, spacing: 12) {
                ForEach(Self.timerKinds) { kind in timerTile(kind) }
            }
            .popoverTip(TinytideTips.holdForMore, arrowEdge: .top)

            groupTitle(String(localized: "Add Entry"))
                .padding(.top, 6)
            LazyVGrid(columns: columns, spacing: 12) {
                entryTile(.bottle)
                entryTile(.diaper)
                entryTile(.solids)
                entryTile(.activity)
                entryTile(.growth)
                healthTile
                entryTile(.note)
            }
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    /// A labeled header button rather than a hidden long-press: logging
    /// something that already happened is common ("she fell asleep 10 minutes ago").
    private var logPastMenu: some View {
        Menu {
            ForEach(Self.timerKinds) { kind in
                Button {
                    editor = EditorRoute(kind: kind, mode: .manual)
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Log Past")
                Image(systemName: "chevron.down").font(.caption2.bold()).accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            // A comfortable target for a text-only button.
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .fixedSize()
    }

    // MARK: Tiles

    /// Starts `kind` on tap, or stops it when it is already running.
    private func timerTile(_ kind: EventKind) -> some View {
        Group {
            if let event = runningTimers(of: kind).first {
                let record = event.record
                Button {
                    stop(event)
                } label: {
                    QuickActionTile(
                        title: kind.title,
                        systemImage: kind.systemImage,
                        color: kind.color,
                        badge: .stop,
                        elapsed: { now in kind == .nursing ? record.nursingTotal(at: now) : record.duration(at: now) }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(kind == .sleep ? Text("Ends the sleep") : Text("Stops the timer"))
            } else {
                Button {
                    if kind == .nursing { startNursing(suggestedSide) } else { startTimer(kind, nil) }
                } label: {
                    QuickActionTile(
                        title: kind.title,
                        subtitle: kind == .nursing ? String(localized: "Next Side: \(suggestedSide.shortTitle)") : nil,
                        systemImage: kind.systemImage,
                        color: kind.color,
                        badge: .start
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Starts a timer. Touch and hold for more options."))
                .contextMenu {
                    if kind == .nursing {
                        ForEach([BreastSide.left, .right], id: \.self) { side in
                            Button {
                                usedHold()
                                startNursing(side)
                            } label: {
                                Label(String(localized: "Start \(side.title)"), systemImage: "play.fill")
                            }
                        }
                    } else {
                        Button {
                            usedHold()
                            editor = EditorRoute(kind: kind, mode: .timer)
                        } label: {
                            Label("Start with Details", systemImage: "timer")
                        }
                    }
                    Button {
                        usedHold()
                        editor = EditorRoute(kind: kind, mode: .manual)
                    } label: {
                        Label("Log Past", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        }
    }

    /// Opens the form for `kind` with Save at hand ("Log Past"; the Timer
    /// segment is one tap away). A running bottle opens that bottle instead, to
    /// add the amount or stop it, and says so with a pencil badge. Activities can
    /// overlap, so the tile always adds a new one and only names what is running.
    private func entryTile(_ kind: EventKind) -> some View {
        let active = runningTimers(of: kind)
        let open = kind == .bottle ? active.first : nil
        let openRecord = open?.record
        return Button {
            if let open {
                editor = EditorRoute(kind: kind, existing: open)
            } else {
                editor = EditorRoute(kind: kind, mode: .manual)
            }
        } label: {
            QuickActionTile(
                title: kind.title,
                subtitle: kind == .activity ? active.first.map { $0.record.displayTitle } : nil,
                systemImage: kind.systemImage,
                color: kind.color,
                badge: openRecord == nil ? .add : .edit,
                elapsed: openRecord.map { record in { (now: Date) in record.duration(at: now) } }
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(open == nil ? Text("Opens a form") : Text("Opens the running bottle"))
    }

    /// The hint about touch-and-hold is no longer needed once it has been used.
    private func usedHold() {
        TinytideTips.holdForMore.invalidate(reason: .actionPerformed)
    }

    private var healthTile: some View {
        Button {
            let last = records.first { Self.healthKinds.contains($0.kind) }?.kind
            editor = EditorRoute(kind: last ?? .temperature, choices: Self.healthKinds)
        } label: {
            QuickActionTile(
                title: String(localized: "Health"),
                systemImage: "cross.case.fill",
                color: EventKind.medication.color,
                badge: .add
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens a form"))
    }
}

struct QuickActionTile: View {
    /// What a tap does, shown in the tile's corner.
    enum Badge {
        /// Starts a timer.
        case start
        /// Stops the running timer.
        case stop
        /// Opens a form.
        case add
        /// Opens the running entry of this kind.
        case edit
    }

    var title: String
    var subtitle: String?
    var systemImage: String
    var color: Color
    var badge: Badge
    /// Shown counting up under the title while a timer runs.
    var elapsed: ((Date) -> TimeInterval)?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isActive: Bool { badge == .stop || badge == .edit }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        VStack(spacing: 4) {
            KindIcon(systemImage: systemImage, color: color, size: 40)
                .padding(.bottom, 2)
            Text(title)
                .font(.caption)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary)
            // Always laid out so every tile in a row is the same height.
            Group {
                if let elapsed {
                    ClockTimeline(every: 1) { now in
                        Text(Fmt.clock(elapsed(now)))
                            .monospacedDigit()
                            // "18 minutes" rather than a clock time.
                            .accessibilityLabel(Text(Fmt.duration(elapsed(now), style: .full)))
                    }
                    .foregroundStyle(color)
                } else {
                    Text(subtitle ?? " ").foregroundStyle(Color.secondary)
                }
            }
            .font(.caption2.weight(isActive ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityHidden(subtitle == nil && elapsed == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(isActive ? color.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: shape)
        .overlay {
            if isActive { shape.strokeBorder(color, lineWidth: 2) }
        }
        // Small and tucked into the corner so it clears the icon even on the
        // narrow four-column tiles.
        .overlay(alignment: .topTrailing) {
            badgeView.padding(4)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isActive ? Text("Running") : Text(verbatim: ""))
    }

    @ViewBuilder
    private var badgeView: some View {
        switch badge {
        case .start:
            badgeIcon("play.fill", foreground: color, background: color.opacity(0.15))
        case .stop:
            badgeIcon("stop.fill", foreground: .white, background: color)
        case .add:
            badgeIcon("plus", foreground: .secondary, background: Color(.tertiarySystemFill))
        case .edit:
            badgeIcon("pencil", foreground: .white, background: color)
        }
    }

    private func badgeIcon(_ name: String, foreground: Color, background: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 16, height: 16)
            .background(background, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Status

struct StatusCards: View {
    var records: [EventRecord]
    var now: Date

    var body: some View {
        let lastFeed = records.first { $0.kind.isFeeding }
        let lastDiaper = records.first { $0.kind == .diaper }
        let sleeps = records.filter { $0.kind == .sleep }
        let sleeping = sleeps.first { $0.isOngoing }
        let lastWake = sleeps.compactMap(\.endDate).max()
        let lastNursing = records.first { $0.kind == .nursing }

        VStack(spacing: 12) {
            // An HStack proposes its full height to both tiles, so the shorter
            // one stretches to match.
            HStack(alignment: .top, spacing: 12) {
                StatusTile(
                    title: String(localized: "Last Feed"),
                    value: lastFeed.map { Fmt.ago($0.startDate, now: now) } ?? "—",
                    detail: lastFeed.map { "\($0.displayTitle) · \($0.detailText(now: now))" },
                    footnote: lastNursing.map { _ in String(localized: "Next Side: \(EventRecord.suggestedNextSide(after: lastNursing).title)") },
                    // The icon follows what the last feed was.
                    kind: lastFeed?.kind ?? .bottle
                )
                StatusTile(
                    title: String(localized: "Last Diaper"),
                    value: lastDiaper.map { Fmt.ago($0.startDate, now: now) } ?? "—",
                    detail: lastDiaper?.diaperType?.title,
                    footnote: nil,
                    kind: .diaper
                )
            }
            StatusTile(
                    title: sleeping != nil ? String(localized: "Asleep for") : String(localized: "Awake for"),
                    value: sleeping.map { Fmt.duration($0.duration(at: now)) } ?? lastWake.map { Fmt.duration(now.timeIntervalSince($0)) } ?? "—",
                    detail: sleeping.map { String(localized: "Since \(Fmt.time($0.startDate))") } ?? lastWake.map { String(localized: "Woke at \(Fmt.time($0))") },
                    footnote: nil,
                    kind: .sleep
            )
        }
    }
}

struct StatusTile: View {
    var title: String
    var value: String
    var detail: String?
    var footnote: String?
    var kind: EventKind
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind.color)
            Text(value).font(.title3.bold()).lineLimit(typeSize.isAccessibilitySize ? 2 : 1).minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let footnote {
                Text(footnote).font(.caption2.weight(.medium)).foregroundStyle(.pink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SweetSpotCard: View {
    var baby: BabyRecord
    var records: [EventRecord]
    var now: Date
    @State private var showingInfo = false

    var body: some View {
        let sleeps = records.filter { $0.kind == .sleep }
        let prediction = sleeps.contains(where: \.isOngoing) ? nil : NapPredictor.predict(
            birthDate: baby.birthDate, sleeps: sleeps, now: now, classifier: AppSettings.sleepClassifier
        )
        if prediction == nil && sleeps.isEmpty {
            // Nothing to predict from yet; say what will appear here.
            Card(title: String(localized: "Next Nap Sweet Spot"), systemImage: "sparkles", tint: .indigo) {
                Text("Log a sleep to get nap-time suggestions based on age and your baby's rhythm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        if let prediction {
            Card(title: prediction.isBedtime ? String(localized: "Suggested Bedtime") : String(localized: "Next Nap Sweet Spot"),
                 systemImage: "sparkles", tint: .indigo) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(Fmt.time(prediction.earliest)) – \(Fmt.time(prediction.latest))")
                        .font(.title2.bold())
                    Spacer()
                    Text(status(prediction))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(now > prediction.latest ? .orange : .indigo)
                }
                Text(prediction.isPersonalized
                     ? String(localized: "Based on age and this baby's recent wake windows.")
                     : String(localized: "Based on typical wake windows for this age."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func status(_ p: NapPrediction) -> String {
        if now < p.earliest { return String(localized: "in \(Fmt.duration(p.earliest.timeIntervalSince(now)))") }
        if now <= p.latest { return String(localized: "Now") }
        return String(localized: "Overtired Risk")
    }
}

struct TodayCard: View {
    var records: [EventRecord]
    var now: Date

    var body: some View {
        let today = Statistics.dailySummaries(
            events: records, from: now, to: now, now: now, classifier: AppSettings.sleepClassifier
        ).first ?? DailySummary(day: now)
        Card(title: String(localized: "Today"), systemImage: "sun.max.fill", tint: .orange) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    metric(String(localized: "Sleep"), Fmt.duration(today.totalSleep), .sleep)
                    metric(String(localized: "Naps"), "\(today.napCount)", .sleep)
                }
                GridRow {
                    metric(String(localized: "Feeds"), "\(today.feedCount)", .nursing)
                    metric(String(localized: "Bottle"), Fmt.volume(today.bottleVolumeML), .bottle)
                }
                GridRow {
                    metric(String(localized: "Wet"), "\(today.wetDiapers)", .diaper)
                    metric(String(localized: "Dirty"), "\(today.dirtyDiapers)", .diaper)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ kind: EventKind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(kind.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecentCard: View {
    var events: [Event]
    var onSelect: (Event) -> Void
    /// Nil when the entries can't be deleted (a read-only caregiver).
    var onDelete: ((Event) -> Void)?

    var body: some View {
        if !events.isEmpty {
            Card(title: String(localized: "Recent"), systemImage: "clock.fill", tint: .gray) {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        row(event)
                        .contextMenu {
                            Button {
                                onSelect(event)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            if let onDelete {
                                Button(role: .destructive) {
                                    onDelete(event)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        if event != events.last { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ event: Event) -> some View {
        if let onDelete {
            SwipeToDeleteRow(onTap: { onSelect(event) }, onDelete: { onDelete(event) }) {
                EventRow(event: event)
                    .padding(.vertical, 6)
            }
        } else {
            EventRow(event: event)
                .padding(.vertical, 6)
                .onTapGesture { onSelect(event) }
        }
    }
}

struct EventRow: View {
    @ObservedObject var event: Event

    var body: some View {
        let record = event.record
        HStack(spacing: 12) {
            KindIcon(systemImage: record.displayImage, color: record.kind.color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.displayTitle).font(.subheadline.weight(.semibold))
                    if record.isOngoing {
                        Text("Running").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(record.kind.color, in: Capsule())
                    }
                }
                let detail = record.detailText()
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeText(record)).font(.caption.monospacedDigit())
                if let author = record.authorName {
                    Text(author).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if record.photoData != nil {
                Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func timeText(_ r: EventRecord) -> String {
        // A range only when there was one (bottles logged without a duration
        // end when they start).
        if r.kind.hasDuration, let end = r.endDate, r.kind != .nursing, end.timeIntervalSince(r.startDate) >= 60 {
            return "\(Fmt.time(r.startDate)) – \(Fmt.time(end))"
        }
        return Fmt.time(r.startDate)
    }
}
