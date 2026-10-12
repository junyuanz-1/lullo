import BabyCore
import Charts
import CoreData
import SwiftUI

struct TrendsView: View {
    @ObservedObject var baby: Baby
    @State private var range = 7

    var body: some View {
        NavigationStack {
            TrendsContent(baby: baby, range: range)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
                // One tap to change the range, instead of opening a menu first.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Picker("Range", selection: $range) {
                        Text("7 Days").tag(7)
                        Text("14 Days").tag(14)
                        Text("30 Days").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                }
                .toolbar {
                    ToolbarItem(placement: .principal) { BabySwitcher(baby: baby) }
                }
        }
    }
}

private struct TrendsContent: View {
    @ObservedObject var baby: Baby
    let range: Int
    @FetchRequest private var events: FetchedResults<Event>
    private let from: Date
    private let to: Date

    init(baby: Baby, range: Int) {
        self.baby = baby
        self.range = range
        let calendar = Calendar.current
        to = AppClock.now
        from = calendar.date(byAdding: .day, value: -(range - 1), to: calendar.startOfDay(for: to))!
        // Start a day early so night sleep that began the evening before is counted.
        let fetchFrom = calendar.date(byAdding: .day, value: -1, to: from)!
        _events = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: true)],
            predicate: NSPredicate(
                format: "baby == %@ AND (startDate >= %@ OR (endDate == nil AND kind IN %@))",
                baby, fetchFrom as NSDate, EventKind.allCases.filter(\.supportsTimer).map(\.rawValue)
            )
        )
    }

    var body: some View {
        let records = events.map(\.record)
        let now = AppClock.now
        let classifier = AppSettings.sleepClassifier
        let days = Statistics.dailySummaries(events: records, from: from, to: to, now: now, classifier: classifier)
        // Today is still in progress, so it would pull every average down; until
        // a full day has been logged there are no averages to show.
        let average = Statistics.average(days.filter { !$0.isToday })
        let schedules = Statistics.schedules(events: records, from: from, to: to, now: now)
        let ageMonths = baby.record.ageInMonths(at: AppClock.now)

        if !days.contains(where: \.hasData) {
            ContentUnavailableView(
                "No Trends Yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Daily patterns appear here once you start logging sleep, feeds and diapers.")
            )
            .background(Color(.systemGroupedBackground))
        } else {
            charts(days: days, average: average, schedules: schedules, ageMonths: ageMonths)
        }
    }

    private func charts(days: [DailySummary], average: DailySummary?, schedules: [DaySchedule], ageMonths: Double) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if let average {
                    AveragesCard(average: average, recommended: NapPredictor.recommendedDailySleepHours(ageInMonths: ageMonths))
                }
                Card(title: String(localized: "Daily Schedule"), systemImage: "calendar.day.timeline.left", tint: .indigo) {
                    ScheduleChart(rows: Array(schedules.suffix(min(range, 14)).reversed()))
                }
                SleepChart(days: days, recommended: NapPredictor.recommendedDailySleepHours(ageInMonths: ageMonths))
                FeedingChart(days: days)
                DiaperChart(days: days)
                if days.contains(where: { $0.pumpingCount > 0 }) {
                    PumpingChart(days: days)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct AveragesCard: View {
    var average: DailySummary
    var recommended: ClosedRange<Double>

    var body: some View {
        Card(title: String(localized: "Daily Averages"), systemImage: "chart.bar.fill", tint: .blue) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    item(String(localized: "Total Sleep"), Fmt.duration(average.totalSleep), .indigo)
                    item(String(localized: "Naps"), "\(average.napCount) · \(Fmt.duration(average.napSleep))", .indigo)
                }
                GridRow {
                    item(String(localized: "Night Sleep"), Fmt.duration(average.nightSleep), .indigo)
                    item(String(localized: "Feeds"), "\(average.feedCount)", .pink)
                }
                GridRow {
                    item(String(localized: "Bottle"), Fmt.volume(average.bottleVolumeML), .orange)
                    item(String(localized: "Diapers"), "\(average.diaperCount)", .teal)
                }
            }
            Text("Recommended total sleep for this age: \(Fmt.number(recommended.lowerBound, digits: 0))–\(Fmt.number(recommended.upperBound, digits: 0)) h")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Today is still in progress: it is shown faded in the charts and left out of the averages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func item(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Huckleberry-style 24 h rows: one line per day, sleep and feeds as blocks, other events as ticks.
struct ScheduleChart: View {
    var rows: [DaySchedule]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                dateLabel(nil)
                HStack(spacing: 0) {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(hourLabel(hour))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    dateLabel(row.day)
                    GeometryReader { geo in
                        let width = geo.size.width
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(.tertiarySystemFill))
                            ForEach(Array(row.blocks.enumerated()), id: \.offset) { _, block in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(block.kind.color.opacity(block.kind == .sleep ? 0.85 : 1))
                                    .frame(width: max(2, width * (block.end - block.start) / row.dayLength),
                                           height: block.kind == .sleep ? 16 : 8)
                                    .offset(x: width * block.start / row.dayLength)
                            }
                            ForEach(Array(row.marks.enumerated()), id: \.offset) { _, mark in
                                Capsule()
                                    .fill(mark.kind.color)
                                    .frame(width: 3, height: mark.kind == .diaper ? 8 : 12)
                                    .offset(x: width * mark.offset / row.dayLength - 1.5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
                }
            }
            FlowLayout(spacing: 12, lineSpacing: 6) {
                legend(.sleep)
                legend(.nursing)
                legend(.bottle)
                legend(.diaper)
            }
            .padding(.top, 4)
        }
    }

    /// The date column is as wide as the widest possible date, so every row's
    /// bar starts at the same x and the bars take all the remaining width.
    private func dateLabel(_ day: Date?) -> some View {
        Text(Self.widestDate)
            .hidden()
            .overlay(alignment: .leading) {
                if let day {
                    Text(day.formatted(.dateTime.month(.defaultDigits).day()))
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private static let widestDate: String = {
        let date = Calendar.current.date(from: DateComponents(year: 2024, month: 12, day: 31)) ?? Date()
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }()

    private func legend(_ kind: EventKind) -> some View {
        HStack(spacing: 4) {
            Circle().fill(kind.color).frame(width: 8, height: 8)
            Text(kind.title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

private struct SleepChart: View {
    var days: [DailySummary]
    var recommended: ClosedRange<Double>

    var body: some View {
        Card(title: String(localized: "Sleep"), systemImage: EventKind.sleep.systemImage, tint: .indigo) {
            Chart {
                ForEach([recommended.lowerBound, recommended.upperBound], id: \.self) { hours in
                    RuleMark(y: .value("Recommended", hours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.green)
                }
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.nightSleep / 3600))
                        .foregroundStyle(by: .value("Type", String(localized: "Night")))
                        .opacity(day.chartOpacity)
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.napSleep / 3600))
                        .foregroundStyle(by: .value("Type", String(localized: "Naps")))
                        .opacity(day.chartOpacity)
                }
            }
            .chartForegroundStyleScale([String(localized: "Night"): Color.indigo, String(localized: "Naps"): Color.purple.opacity(0.6)])
            .chartYAxisLabel(String(localized: "hours"))
            .frame(height: 200)
        }
    }
}

private struct FeedingChart: View {
    var days: [DailySummary]

    var body: some View {
        Card(title: String(localized: "Feeding"), systemImage: EventKind.bottle.systemImage, tint: .orange) {
            Chart(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.nursingCount))
                    .foregroundStyle(by: .value("Type", EventKind.nursing.title))
                    .opacity(day.chartOpacity)
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.bottleCount))
                    .foregroundStyle(by: .value("Type", EventKind.bottle.title))
                    .opacity(day.chartOpacity)
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.solidsCount))
                    .foregroundStyle(by: .value("Type", EventKind.solids.title))
                    .opacity(day.chartOpacity)
            }
            .chartForegroundStyleScale([
                EventKind.nursing.title: Color.pink,
                EventKind.bottle.title: Color.orange,
                EventKind.solids.title: Color.green,
            ])
            .frame(height: 180)

            if days.contains(where: { $0.bottleVolumeML > 0 }) {
                Text("Bottle Volume").font(.subheadline.weight(.semibold))
                Chart {
                    // The line stops at yesterday; today so far is a lighter dot,
                    // so a half-finished day doesn't read as a sudden drop.
                    ForEach(days.filter { !$0.isToday }) { day in
                        LineMark(x: .value("Day", day.day, unit: .day), y: .value("Volume", displayVolume(day.bottleVolumeML)))
                            .foregroundStyle(.orange)
                            .symbol(.circle)
                    }
                    ForEach(days.filter(\.isToday)) { day in
                        PointMark(x: .value("Day", day.day, unit: .day), y: .value("Volume", displayVolume(day.bottleVolumeML)))
                            .foregroundStyle(.orange.opacity(0.55))
                    }
                }
                .chartYAxisLabel(AppSettings.unitSystem == .metric ? String(localized: "ml") : String(localized: "oz"))
                .frame(height: 140)
            }
            if days.contains(where: { $0.nursingDuration > 0 }) {
                Text("Nursing Minutes").font(.subheadline.weight(.semibold))
                Chart(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.nursingDuration / 60))
                        .foregroundStyle(.pink.gradient)
                        .opacity(day.chartOpacity)
                }
                .frame(height: 140)
            }
        }
    }

    private func displayVolume(_ ml: Double) -> Double {
        AppSettings.unitSystem == .metric ? ml : UnitConversion.ounces(fromML: ml)
    }
}

private struct DiaperChart: View {
    var days: [DailySummary]

    var body: some View {
        Card(title: String(localized: "Diapers"), systemImage: EventKind.diaper.systemImage, tint: .teal) {
            Chart(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Count", day.wetDiapers))
                    .foregroundStyle(by: .value("Type", String(localized: "Wet")))
                    .opacity(day.chartOpacity)
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Count", day.dirtyDiapers))
                    .foregroundStyle(by: .value("Type", String(localized: "Dirty")))
                    .opacity(day.chartOpacity)
            }
            .chartForegroundStyleScale([String(localized: "Wet"): Color.teal, String(localized: "Dirty"): Color.brown])
            .frame(height: 180)
            Text("Newborns usually have 6 or more wet diapers a day after the first week.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PumpingChart: View {
    var days: [DailySummary]

    var body: some View {
        Card(title: String(localized: "Pumping"), systemImage: EventKind.pumping.systemImage, tint: .purple) {
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Volume", AppSettings.unitSystem == .metric ? day.pumpingVolumeML : UnitConversion.ounces(fromML: day.pumpingVolumeML))
                )
                .foregroundStyle(.purple.gradient)
                .opacity(day.chartOpacity)
            }
            .chartYAxisLabel(AppSettings.unitSystem == .metric ? String(localized: "ml") : String(localized: "oz"))
            .frame(height: 160)
        }
    }
}

private extension DailySummary {
    var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: AppClock.now) }

    /// Today is still in progress, so its bars are faded (enough to stay
    /// visible on a dark background).
    var chartOpacity: Double { isToday ? 0.55 : 1 }
}
