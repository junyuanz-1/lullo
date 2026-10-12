import AppIntents
import BabyCore
import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let baby: BabySnapshot?
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), baby: .preview())
    }

    func snapshot(for configuration: SelectBabyIntent, in context: Context) async -> StatusEntry {
        let baby = resolve(configuration)
        return StatusEntry(date: Date(), baby: baby ?? (context.isPreview ? .preview() : nil))
    }

    func timeline(for configuration: SelectBabyIntent, in context: Context) async -> Timeline<StatusEntry> {
        let snapshot = SharedContainer.loadSnapshot()
        let baby = snapshot.baby(configuration.baby.flatMap { UUID(uuidString: $0.id) })
        let now = Date()
        // "x ago" labels are computed per entry, so add an entry every 5 minutes.
        let entries = (0..<36).map { i in
            let date = now.addingTimeInterval(Double(i) * 300)
            return StatusEntry(date: date, baby: baby.map { Self.today($0, madeAt: snapshot.generatedAt, shownAt: date) })
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func resolve(_ configuration: SelectBabyIntent) -> BabySnapshot? {
        SharedContainer.loadSnapshot().baby(configuration.baby.flatMap { UUID(uuidString: $0.id) })
    }

    /// The snapshot's "today" totals belong to the day it was made. Shown after
    /// midnight (the app not opened since), the new day starts from zero instead
    /// of repeating yesterday's numbers.
    private static func today(_ baby: BabySnapshot, madeAt: Date, shownAt date: Date) -> BabySnapshot {
        guard !Calendar.current.isDate(madeAt, inSameDayAs: date), date > madeAt else { return baby }
        var baby = baby
        // A sleep still running counts from midnight.
        let midnight = Calendar.current.startOfDay(for: date)
        baby.today.sleep = baby.runningSleep.map { date.timeIntervalSince(max(midnight, $0.startDate)) } ?? 0
        baby.today.feeds = 0
        baby.today.bottleML = 0
        baby.today.wetDiapers = 0
        baby.today.dirtyDiapers = 0
        return baby
    }
}

struct StatusWidget: Widget {
    let kind = "StatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectBabyIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Baby Status")
        .description("Time since the last feed, diaper and sleep, with quick logging buttons.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        if let baby = entry.baby {
            switch family {
            case .systemSmall:
                SmallStatusView(baby: baby, now: entry.date)
            case .systemMedium:
                MediumStatusView(baby: baby, now: entry.date)
            case .systemLarge:
                LargeStatusView(baby: baby, now: entry.date)
            case .accessoryRectangular:
                RectangularStatusView(baby: baby, now: entry.date)
            case .accessoryCircular:
                CircularStatusView(baby: baby, now: entry.date)
            case .accessoryInline:
                Text(inlineText(baby: baby, now: entry.date))
            default:
                SmallStatusView(baby: baby, now: entry.date)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(.indigo)
                Text("Open the app to add your baby.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func inlineText(baby: BabySnapshot, now: Date) -> String {
        guard let feed = baby.lastFeed else { return baby.name }
        return String(localized: "Fed \(Fmt.ago(feed.date, now: now))")
    }
}

// MARK: - Rows

private struct StatusRow: View {
    var systemImage: String
    var color: Color
    var title: String
    var value: String
    var timerStart: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                if let timerStart {
                    Text(timerStart, style: .timer)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text(value).font(.subheadline.weight(.semibold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

private struct StatusRows: View {
    let baby: BabySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nursing = baby.runningNursing {
                StatusRow(systemImage: EventKind.nursing.systemImage, color: .pink,
                          title: String(localized: "Nursing"), value: Fmt.clock(nursingTotal(nursing, now)),
                          timerStart: nursingTimerStart(nursing))
            } else {
                StatusRow(systemImage: EventKind.bottle.systemImage, color: .orange,
                          title: String(localized: "Last Feed"),
                          value: baby.lastFeed.map { Fmt.ago($0.date, now: now) } ?? "—")
            }
            if let sleep = baby.runningSleep {
                StatusRow(systemImage: EventKind.sleep.systemImage, color: .indigo,
                          title: String(localized: "Sleeping"), value: "", timerStart: sleep.startDate)
            } else {
                StatusRow(systemImage: "sun.max.fill", color: .yellow,
                          title: String(localized: "Awake for"),
                          value: baby.awakeSince.map { Fmt.duration(now.timeIntervalSince($0)) } ?? "—")
            }
            StatusRow(systemImage: EventKind.diaper.systemImage, color: .teal,
                      title: String(localized: "Last Diaper"),
                      value: baby.lastDiaper.map { Fmt.ago($0.date, now: now) } ?? "—")
        }
    }
}

private func nursingTotal(_ timer: BabySnapshot.RunningTimer, _ now: Date) -> TimeInterval {
    var total = timer.leftDuration + timer.rightDuration
    if let since = timer.activeSideStartedAt, timer.activeSide != nil { total += now.timeIntervalSince(since) }
    return total
}

private func nursingTimerStart(_ timer: BabySnapshot.RunningTimer) -> Date? {
    guard let since = timer.activeSideStartedAt, timer.activeSide != nil else { return nil }
    return since.addingTimeInterval(-(timer.leftDuration + timer.rightDuration))
}

// MARK: - Buttons

private struct QuickButtons: View {
    let baby: BabySnapshot
    var compact = false
    /// Adds a Fussy button and puts all five in one row; only the large widget
    /// is wide enough (and one row keeps it from growing taller).
    var showsFussy = false

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: showsFussy ? 5 : 2)
        LazyVGrid(columns: columns, spacing: 6) {
            if let sleep = baby.runningSleep {
                button(intent: StopTimerIntent(eventID: sleep.id), title: String(localized: "Wake"), image: "sun.max.fill", color: .indigo)
            } else {
                button(intent: StartSleepIntent(babyID: baby.id), title: String(localized: "Sleep"), image: EventKind.sleep.systemImage, color: .indigo)
            }
            if let nursing = baby.runningNursing {
                button(intent: StopTimerIntent(eventID: nursing.id), title: String(localized: "Done"), image: "checkmark", color: .pink)
            } else {
                button(intent: StartNursingIntent(babyID: baby.id, side: baby.suggestedSide),
                       title: String(localized: "Nurse \(baby.suggestedSide.shortTitle)"), image: EventKind.nursing.systemImage, color: .pink)
            }
            button(intent: LogDiaperIntent(babyID: baby.id, type: .wet), title: DiaperType.wet.title, image: DiaperType.wet.systemImage, color: .teal)
            button(intent: LogDiaperIntent(babyID: baby.id, type: .dirty), title: DiaperType.dirty.title, image: DiaperType.dirty.systemImage, color: .brown)
            if showsFussy {
                button(intent: LogFussyIntent(babyID: baby.id), title: EventKind.fussy.title, image: EventKind.fussy.systemImage, color: EventKind.fussy.color)
            }
        }
    }

    private func button(intent: some AppIntent, title: String, image: String, color: Color) -> some View {
        Button(intent: intent) {
            VStack(spacing: 2) {
                Image(systemName: image).font(.system(size: compact ? 13 : 15, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 34 : 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Families

private struct SmallStatusView: View {
    let baby: BabySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(baby.name).font(.headline).lineLimit(1)
            StatusRows(baby: baby, now: now)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumStatusView: View {
    let baby: BabySnapshot
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(baby.name).font(.headline).lineLimit(1)
                StatusRows(baby: baby, now: now)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            QuickButtons(baby: baby)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct LargeStatusView: View {
    let baby: BabySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(baby.name).font(.title3.bold())
                Spacer()
                Text(Fmt.age(birthDate: baby.birthDate, at: now)).font(.caption).foregroundStyle(.secondary)
            }
            StatusRows(baby: baby, now: now)
            if let nap = baby.nextNap {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(.indigo)
                    Text(nap.isBedtime ? String(localized: "Bedtime") : String(localized: "Next Nap"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "\(Fmt.time(nap.earliest)) – \(Fmt.time(nap.latest))")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Divider()
            HStack {
                total(String(localized: "Sleep"), Fmt.duration(baby.today.sleep))
                total(String(localized: "Feeds"), "\(baby.today.feeds)")
                total(String(localized: "Wet"), "\(baby.today.wetDiapers)")
                total(String(localized: "Dirty"), "\(baby.today.dirtyDiapers)")
            }
            Spacer(minLength: 0)
            QuickButtons(baby: baby, showsFussy: true)
        }
    }

    private func total(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RectangularStatusView: View {
    let baby: BabySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(baby.name).font(.headline).widgetAccentable()
            if let feed = baby.lastFeed {
                Label(Fmt.ago(feed.date, now: now), systemImage: EventKind.bottle.systemImage)
                    .font(.caption)
            }
            if let sleep = baby.runningSleep {
                Label {
                    Text(sleep.startDate, style: .timer)
                } icon: {
                    Image(systemName: EventKind.sleep.systemImage)
                }
                .font(.caption)
            } else if let nap = baby.nextNap {
                Label(String(localized: "Nap \(Fmt.time(nap.earliest))"), systemImage: "sparkles")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularStatusView: View {
    let baby: BabySnapshot
    let now: Date

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: baby.runningSleep != nil ? EventKind.sleep.systemImage : EventKind.bottle.systemImage)
                    .font(.caption)
                if let sleep = baby.runningSleep {
                    Text(Fmt.duration(now.timeIntervalSince(sleep.startDate)))
                        .font(.system(size: 11, weight: .semibold))
                } else if let feed = baby.lastFeed {
                    Text(Fmt.duration(now.timeIntervalSince(feed.date)))
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Text(verbatim: "—")
                }
            }
            .minimumScaleFactor(0.6)
            .padding(4)
        }
    }
}
