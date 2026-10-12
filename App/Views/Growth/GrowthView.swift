import BabyCore
import Charts
import CoreData
import SwiftUI

struct GrowthView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var measurements: FetchedResults<Event>
    @State private var metric: GrowthMetric = .weight
    @State private var editor: EditorRoute?

    init(baby: Baby) {
        self.baby = baby
        _measurements = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: true)],
            predicate: NSPredicate(format: "baby == %@ AND kind == %@", baby, EventKind.growth.rawValue)
        )
    }

    var body: some View {
        let record = baby.record
        let points: [GrowthPoint] = measurements.compactMap { event in
            let r = event.record
            guard let value = metric.value(of: r) else { return nil }
            return GrowthPoint(event: event, month: record.ageInMonths(at: r.startDate), value: value)
        }

        NavigationStack {
            List {
                Section {
                    Picker("Measurement", selection: $metric) {
                        ForEach(GrowthMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    GrowthChart(
                        metric: metric,
                        sex: record.sex,
                        points: points.map { ($0.month, $0.value) },
                        maxMonth: min(GrowthStandards.maxMonth, max(6, (record.ageInMonths().rounded(.up)) + 2))
                    )
                    .frame(height: 280)
                    .padding(.vertical, 8)
                } footer: {
                    if record.sex == .unspecified {
                        Text("Set your baby's sex in the profile to compare with WHO growth standards.")
                    } else {
                        Text("Shaded bands show the 3rd–97th and 15th–85th percentiles of the WHO Child Growth Standards (birth to 24 months).")
                    }
                }

                Section("Measurements") {
                    if points.isEmpty {
                        Text("No measurements yet.").foregroundStyle(.secondary)
                    }
                    ForEach(points.reversed()) { point in
                        Button {
                            editor = EditorRoute(kind: .growth, existing: point.event)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(format(point.value)).font(.headline)
                                    Text((point.event.startDate ?? Date()).formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let p = GrowthStandards.percentile(of: point.value, metric: metric, sex: record.sex, ageInMonths: point.month) {
                                    Text(Fmt.percentile(p))
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Growth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = EditorRoute(kind: .growth)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel(Text("Add Measurement"))
                }
            }
            .sheet(item: $editor) { route in
                NavigationStack {
                    EventEditorView(baby: baby, kind: route.kind, existing: route.existing)
                }
            }
        }
    }

    private func format(_ value: Double) -> String {
        switch metric {
        case .weight: return Fmt.weight(value)
        case .length, .headCircumference: return Fmt.length(value)
        }
    }
}

struct GrowthPoint: Identifiable {
    let event: Event
    let month: Double
    let value: Double
    var id: NSManagedObjectID { event.objectID }
}

struct GrowthChart: View {
    var metric: GrowthMetric
    var sex: Sex
    var points: [(month: Double, value: Double)]
    var maxMonth: Double

    private struct Band: Identifiable {
        var id: Double { month }
        var month: Double
        var p3: Double, p15: Double, p50: Double, p85: Double, p97: Double
    }

    private var bands: [Band] {
        let curves = GrowthStandards.chartPercentiles.map { GrowthStandards.curve(for: metric, sex: sex, percentile: $0) }
        guard curves.allSatisfy({ !$0.isEmpty }) else { return [] }
        return curves[0].indices.compactMap { i in
            let month = curves[0][i].month
            guard month <= maxMonth else { return nil }
            return Band(
                month: month,
                p3: display(curves[0][i].value),
                p15: display(curves[1][i].value),
                p50: display(curves[2][i].value),
                p85: display(curves[3][i].value),
                p97: display(curves[4][i].value)
            )
        }
    }

    private func display(_ metricValue: Double) -> Double {
        guard AppSettings.unitSystem == .imperial else { return metricValue }
        return metric == .weight ? UnitConversion.pounds(fromKg: metricValue) : UnitConversion.inches(fromCm: metricValue)
    }

    var body: some View {
        Chart {
            ForEach(bands) { band in
                AreaMark(x: .value("Month", band.month), yStart: .value("P3", band.p3), yEnd: .value("P97", band.p97), series: .value("Band", "outer"))
                    .foregroundStyle(.blue.opacity(0.08))
                AreaMark(x: .value("Month", band.month), yStart: .value("P15", band.p15), yEnd: .value("P85", band.p85), series: .value("Band", "inner"))
                    .foregroundStyle(.blue.opacity(0.12))
                LineMark(x: .value("Month", band.month), y: .value("P50", band.p50), series: .value("Band", "median"))
                    .foregroundStyle(.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Month", point.month), y: .value("Value", display(point.value)), series: .value("Band", "baby"))
                    .foregroundStyle(.pink)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Month", point.month), y: .value("Value", display(point.value)))
                    .foregroundStyle(.pink)
            }
        }
        .chartXScale(domain: 0...maxMonth)
        .chartXAxisLabel(String(localized: "Age (months)"))
        .chartYAxisLabel(unitLabel)
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private var unitLabel: String {
        switch (metric, AppSettings.unitSystem) {
        case (.weight, .metric): return String(localized: "kg")
        case (.weight, .imperial): return String(localized: "lb")
        case (_, .metric): return String(localized: "cm")
        case (_, .imperial): return String(localized: "in")
        }
    }
}
