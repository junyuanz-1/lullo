import BabyCore
import CoreData
import SwiftUI

/// Identifies what the entry editor sheet should show.
struct EditorRoute: Identifiable {
    let id = UUID()
    var kind: EventKind
    var existing: Event?
}

struct HomeView: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject var baby: Baby
    @FetchRequest private var recent: FetchedResults<Event>
    @State private var editor: EditorRoute?

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
                        TimerCard(event: event) { editor = EditorRoute(kind: event.eventKind, existing: event) }
                    }

                    QuickActionsGrid(baby: baby, editor: $editor)

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 16) {
                            StatusCards(records: records, now: context.date)
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
            .toolbar {
                ToolbarItem(placement: .principal) { BabySwitcher(baby: baby) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { route in
                NavigationStack {
                    EventEditorView(baby: baby, kind: route.kind, existing: route.existing)
                }
            }
        }
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
                    NursingControls(event: event, record: record, now: context.date)
                } else {
                    HStack {
                        Text(Fmt.clock(record.duration(at: context.date)))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Button {
                            store.stopTimer(event)
                        } label: {
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
                Button {
                    store.stopTimer(event)
                } label: {
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

struct QuickActionsGrid: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject var baby: Baby
    @Binding var editor: EditorRoute?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            tile(.sleep)
            tile(.nursing)
            tile(.bottle)
            tile(.diaper)
            tile(.pumping)
            tile(.solids)
            tile(.growth)
            Menu {
                ForEach([EventKind.medication, .temperature, .symptom, .vaccine]) { kind in
                    Button {
                        editor = EditorRoute(kind: kind)
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            } label: {
                QuickActionTile(title: String(localized: "Health"), systemImage: "cross.case.fill", color: .red)
            }
            tile(.activity)
            tile(.note)
        }
    }

    private func tile(_ kind: EventKind) -> some View {
        Button {
            editor = EditorRoute(kind: kind)
        } label: {
            QuickActionTile(title: kind.title, systemImage: kind.systemImage, color: kind.color)
        }
        .buttonStyle(.plain)
    }
}

struct QuickActionTile: View {
    var title: String
    var systemImage: String
    var color: Color

    var body: some View {
        VStack(spacing: 6) {
            KindIcon(systemImage: systemImage, color: color, size: 40)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
