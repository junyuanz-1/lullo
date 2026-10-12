import BabyCore
import CoreData
import SwiftUI
import UIKit

/// Identifies what the entry editor sheet should show.
struct EditorRoute: Identifiable {
    let id = UUID()
    var kind: EventKind
    var existing: Event?
    /// Forces the editor into timer or "log past" mode; nil picks the default.
    var mode: EventEditorView.Mode?
}

/// The entry editor in a sheet, sized to the kind of entry.
struct EditorSheet: View {
    @ObservedObject var baby: Baby
    let route: EditorRoute

    var body: some View {
        NavigationStack {
            EventEditorView(baby: baby, kind: route.kind, existing: route.existing, mode: route.mode)
        }
        // Short forms (diaper, bottle, note) open half-height so the Save button
        // is close at hand; drag up for more room.
        .presentationDetents(route.kind.prefersCompactSheet ? [.medium, .large] : [.large])
    }
}

/// A short "done" message with a single Undo button, shown after one-tap actions.
struct UndoToast: Identifiable {
    let id = UUID()
    var message: String
    var undo: () -> Void
}

struct HomeView: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject var baby: Baby
    @FetchRequest private var recent: FetchedResults<Event>
    @State private var editor: EditorRoute?
    @State private var toast: UndoToast?

    init(baby: Baby) {
        self.baby = baby
        let since = Calendar.current.date(byAdding: .day, value: -3, to: Calendar.current.startOfDay(for: Date()))!
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
                        TimerCard(event: event, onEdit: { editor = EditorRoute(kind: event.eventKind, existing: event) }, onStop: { stop(event) })
                    }

                    // What a tired parent checks first: how long since the last feed,
                    // diaper and sleep. The one-tap buttons come right after.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        StatusCards(records: records, now: context.date)
                    }

                    QuickActionsGrid(
                        records: records,
                        running: running.map(\.record),
                        editor: $editor,
                        startTimer: startTimer,
                        startNursing: startNursing,
                        stopRunning: stopRunning,
                        logDiaper: logDiaper
                    )

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 16) {
                            SweetSpotCard(baby: baby.record, records: records, now: context.date)
                            TodayCard(records: records, now: context.date)
                        }
                    }

                    RecentCard(events: Array(recent.prefix(6))) { event in
                        editor = EditorRoute(kind: event.eventKind, existing: event)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if let toast {
                    UndoToastView(toast: toast) {
                        toast.undo()
                        self.toast = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: toast?.id)
            // Each toast stays for a few seconds; a newer one restarts the clock.
            .task(id: toast?.id) {
                guard toast != nil else { return }
                try? await Task.sleep(for: .seconds(6))
                toast = nil
            }
            .toolbar {
                ToolbarItem(placement: .principal) { BabySwitcher(baby: baby) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { route in
                EditorSheet(baby: baby, route: route)
            }
        }
    }

    // MARK: One-tap actions

    private func startTimer(_ kind: EventKind, activityType: ActivityType?) {
        guard let event = store.startTimer(kind, for: baby, activityType: activityType) else { return }
        haptic()
        let message: String
        switch kind {
        case .sleep: message = String(localized: "Sleep started")
        case .pumping: message = String(localized: "Pumping started")
        case .activity: message = String(localized: "\((activityType ?? .play).title) started")
        default: message = String(localized: "Timer started")
        }
        show(message) { store.delete(event) }
    }

    private func startNursing(_ side: BreastSide?) {
        guard let event = store.startNursing(for: baby, side: side) else { return }
        haptic()
        let chosen = event.record.activeSide ?? side ?? .left
        show(String(localized: "Nursing started · \(chosen.title)")) { store.delete(event) }
    }

    /// Stops the running timer of `kind` (the oldest one if several are running).
    private func stopRunning(_ kind: EventKind) {
        guard let event = running.first(where: { $0.eventKind == kind }) else { return }
        stop(event)
    }

    private func stop(_ event: Event) {
        let before = event.record
        store.stopTimer(event)
        haptic()
        if before.kind == .pumping {
            // Amounts are usually known only once pumping ends; ask for them now
            // instead of making the user find the entry again.
            editor = EditorRoute(kind: .pumping, existing: event)
            return
        }
        let message: String
        switch before.kind {
        case .sleep: message = String(localized: "Sleep ended")
        case .nursing: message = String(localized: "Nursing finished")
        case .activity: message = String(localized: "Activity finished")
        default: message = String(localized: "Timer stopped")
        }
        // Saving the earlier record puts the timer back exactly as it was.
        show(message) { store.save(before) }
    }

    private func logDiaper(_ type: DiaperType) {
        guard let event = store.logDiaper(type, for: baby) else { return }
        haptic()
        show(String(localized: "Logged a \(type.title) diaper.")) { store.delete(event) }
    }

    private func show(_ message: String, undo: @escaping () -> Void) {
        toast = UndoToast(message: message, undo: undo)
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

struct UndoToastView: View {
    var toast: UndoToast
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
                Text(Fmt.age(birthDate: baby.birthDate ?? Date())).foregroundStyle(.secondary)
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
    var onEdit: () -> Void
    var onStop: () -> Void

    var body: some View {
        let record = event.record
        Card {
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
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Edit"))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if record.kind == .nursing {
                    NursingControls(event: event, record: record, now: context.date, onStop: onStop)
                } else {
                    HStack {
                        Text(Fmt.clock(record.duration(at: context.date)))
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
        }
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

/// Two rows of big buttons. The frequent ones act on a single tap: sleep,
/// nursing and pumping start (or stop) their timer, a diaper is logged from a
/// short menu. Long-press a tile to log something from earlier or to start
/// with details.
struct QuickActionsGrid: View {
    /// Recent entries, newest first; used for the suggested nursing side.
    var records: [EventRecord]
    var running: [EventRecord]
    @Binding var editor: EditorRoute?
    var startTimer: (EventKind, ActivityType?) -> Void
    var startNursing: (BreastSide?) -> Void
    var stopRunning: (EventKind) -> Void
    var logDiaper: (DiaperType) -> Void

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    private func isRunning(_ kind: EventKind) -> Bool { running.contains { $0.kind == kind } }

    private var suggestedSide: BreastSide {
        EventRecord.suggestedNextSide(after: records.first { $0.kind == .nursing })
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            sleepTile
            nursingTile
            editorTile(.bottle)
            diaperTile
            pumpingTile
            editorTile(.solids)
            activityTile
            moreTile
        }
    }

    // MARK: Tiles

    private var sleepTile: some View {
        timerTile(.sleep, stopTitle: String(localized: "Wake Up"), stopImage: "sun.max.fill") {
            startTimer(.sleep, nil)
        }
    }

    private var nursingTile: some View {
        Group {
            if isRunning(.nursing) {
                Button {
                    stopRunning(.nursing)
                } label: {
                    QuickActionTile(title: String(localized: "Done"), systemImage: "checkmark", color: EventKind.nursing.color)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    startNursing(suggestedSide)
                } label: {
                    QuickActionTile(
                        title: EventKind.nursing.title,
                        subtitle: String(localized: "Next side: \(suggestedSide.shortTitle)"),
                        systemImage: EventKind.nursing.systemImage,
                        color: EventKind.nursing.color
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ForEach([BreastSide.left, .right], id: \.self) { side in
                        Button {
                            startNursing(side)
                        } label: {
                            Label(String(localized: "Start \(side.title)"), systemImage: "play.fill")
                        }
                    }
                    Divider()
                    logPastButton(.nursing)
                }
            }
        }
    }

    private var pumpingTile: some View {
        timerTile(.pumping, stopTitle: String(localized: "Stop"), stopImage: "stop.fill") {
            startTimer(.pumping, nil)
        }
    }

    private var diaperTile: some View {
        Menu {
            ForEach(DiaperType.allCases, id: \.self) { type in
                Button {
                    logDiaper(type)
                } label: {
                    Label(type.title, systemImage: type.systemImage)
                }
            }
            Divider()
            Button {
                editor = EditorRoute(kind: .diaper, mode: .manual)
            } label: {
                Label("More Details", systemImage: "square.and.pencil")
            }
        } label: {
            QuickActionTile(title: EventKind.diaper.title, systemImage: EventKind.diaper.systemImage, color: EventKind.diaper.color)
        }
    }

    private var activityTile: some View {
        Group {
            if isRunning(.activity) {
                Button {
                    stopRunning(.activity)
                } label: {
                    QuickActionTile(title: String(localized: "Stop"), systemImage: "stop.fill", color: EventKind.activity.color)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(ActivityType.allCases, id: \.self) { type in
                        Button {
                            startTimer(.activity, type)
                        } label: {
                            Label(type.title, systemImage: type.systemImage)
                        }
                    }
                    Divider()
                    logPastButton(.activity)
                } label: {
                    QuickActionTile(title: EventKind.activity.title, systemImage: EventKind.activity.systemImage, color: EventKind.activity.color)
                }
            }
        }
    }

    private var moreTile: some View {
        Menu {
            Button {
                editor = EditorRoute(kind: .growth)
            } label: {
                Label(EventKind.growth.title, systemImage: EventKind.growth.systemImage)
            }
            Section(String(localized: "Health")) {
                ForEach([EventKind.medication, .temperature, .symptom, .vaccine]) { kind in
                    Button {
                        editor = EditorRoute(kind: kind)
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            }
            Button {
                editor = EditorRoute(kind: .note)
            } label: {
                Label(EventKind.note.title, systemImage: EventKind.note.systemImage)
            }
        } label: {
            QuickActionTile(title: String(localized: "More"), systemImage: "ellipsis", color: .gray)
        }
    }

    // MARK: Helpers

    /// Starts `kind` on tap, or stops it when it is already running.
    private func timerTile(_ kind: EventKind, stopTitle: String, stopImage: String, start: @escaping () -> Void) -> some View {
        Group {
            if isRunning(kind) {
                Button {
                    stopRunning(kind)
                } label: {
                    QuickActionTile(title: stopTitle, systemImage: stopImage, color: kind.color)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: start) {
                    QuickActionTile(title: kind.title, systemImage: kind.systemImage, color: kind.color)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editor = EditorRoute(kind: kind, mode: .timer)
                    } label: {
                        Label("Start with Details", systemImage: "timer")
                    }
                    logPastButton(kind)
                }
            }
        }
    }

    private func editorTile(_ kind: EventKind) -> some View {
        Button {
            editor = EditorRoute(kind: kind)
        } label: {
            QuickActionTile(title: kind.title, systemImage: kind.systemImage, color: kind.color)
        }
        .buttonStyle(.plain)
    }

    private func logPastButton(_ kind: EventKind) -> some View {
        Button {
            editor = EditorRoute(kind: kind, mode: .manual)
        } label: {
            Label("Log Past", systemImage: "clock.arrow.circlepath")
        }
    }
}

struct QuickActionTile: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            KindIcon(systemImage: systemImage, color: color, size: 40)
                .padding(.bottom, 2)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
            // Always laid out so every tile in a row is the same height.
            Text(subtitle ?? " ")
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
                .accessibilityHidden(subtitle == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatusTile(
                    title: String(localized: "Last Feed"),
                    value: lastFeed.map { Fmt.ago($0.startDate, now: now) } ?? "—",
                    detail: lastFeed.map { "\($0.displayTitle) · \($0.detailText(now: now))" },
                    footnote: lastNursing.map { _ in String(localized: "Next side: \(EventRecord.suggestedNextSide(after: lastNursing).title)") },
                    kind: .bottle
                )
                StatusTile(
                    title: String(localized: "Last Diaper"),
                    value: lastDiaper.map { Fmt.ago($0.startDate, now: now) } ?? "—",
                    detail: lastDiaper?.diaperType?.title,
                    footnote: nil,
                    kind: .diaper
                )
            }
            GridRow {
                StatusTile(
                    title: sleeping != nil ? String(localized: "Asleep for") : String(localized: "Awake for"),
                    value: sleeping.map { Fmt.duration($0.duration(at: now)) } ?? lastWake.map { Fmt.duration(now.timeIntervalSince($0)) } ?? "—",
                    detail: sleeping.map { String(localized: "Since \(Fmt.time($0.startDate))") } ?? lastWake.map { String(localized: "Woke at \(Fmt.time($0))") },
                    footnote: nil,
                    kind: .sleep
                )
                .gridCellColumns(2)
            }
        }
    }
}

struct StatusTile: View {
    var title: String
    var value: String
    var detail: String?
    var footnote: String?
    var kind: EventKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind.color)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let footnote {
                Text(footnote).font(.caption2.weight(.medium)).foregroundStyle(.pink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return String(localized: "Overtired risk")
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

    var body: some View {
        if !events.isEmpty {
            Card(title: String(localized: "Recent"), systemImage: "clock.fill", tint: .gray) {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        Button { onSelect(event) } label: {
                            EventRow(event: event)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if event != events.last { Divider() }
                    }
                }
            }
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
        if r.kind.hasDuration, let end = r.endDate, r.kind != .nursing {
            return "\(Fmt.time(r.startDate)) – \(Fmt.time(end))"
        }
        return Fmt.time(r.startDate)
    }
}
