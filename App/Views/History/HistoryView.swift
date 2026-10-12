import BabyCore
import CoreData
import SwiftUI

struct HistoryView: View {
    @ObservedObject var baby: Baby
    @State private var category: EventCategory?
    @State private var days = 14
    @State private var editor: EditorRoute?
    @State private var toast: UndoToast?

    var body: some View {
        NavigationStack {
            HistoryList(baby: baby, category: category, days: days, editor: $editor, toast: $toast) {
                days += 14
            }
            .undoToast($toast)
            .navigationTitle("Log")
            // Inline title keeps the filter chips right under the toolbar instead of below a large-title gap.
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                CategoryFilter(selection: $category)
                    .background(Color(.systemGroupedBackground))
            }
            .toolbar {
                ToolbarItem(placement: .principal) { BabySwitcher(baby: baby) }
                ToolbarItem(placement: .topBarTrailing) {
                    // Grouped the same way as the filter chips, so the 14 kinds
                    // read as a few short lists instead of one long one.
                    Menu {
                        ForEach(EventCategory.allCases) { category in
                            if category.kinds.count == 1, let kind = category.kinds.first {
                                addButton(kind)
                            } else {
                                Section(category.title) {
                                    ForEach(category.kinds) { kind in addButton(kind) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel(Text("Add Entry"))
                }
            }
            .sheet(item: $editor) { route in
                EditorSheet(baby: baby, route: route)
            }
        }
    }
}

extension HistoryView {
    /// Entries added from the Log are things that already happened, so timer
    /// kinds open in "Log Past" rather than starting a timer.
    fileprivate func addButton(_ kind: EventKind) -> some View {
        Button {
            editor = EditorRoute(kind: kind, mode: .manual)
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
        }
    }
}

private struct CategoryFilter: View {
    @Binding var selection: EventCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "All"), value: nil)
                ForEach(EventCategory.allCases) { category in
                    chip(title: category.title, value: category)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, value: EventCategory?) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemFill)), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryList: View {
    @EnvironmentObject private var store: TrackerStore
    @FetchRequest private var events: FetchedResults<Event>
    @Binding var editor: EditorRoute?
    @Binding var toast: UndoToast?
    var loadMore: () -> Void
    private let isFiltered: Bool
    /// False for a read-only caregiver, who gets no swipe to delete.
    private let canEdit: Bool

    init(baby: Baby, category: EventCategory?, days: Int, editor: Binding<EditorRoute?>, toast: Binding<UndoToast?>, loadMore: @escaping () -> Void) {
        isFiltered = category != nil
        canEdit = TrackerStore.shared.canEdit(baby)
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: AppClock.now))!
        var predicates = [
            NSPredicate(format: "baby == %@", baby),
            NSPredicate(format: "startDate >= %@", since as NSDate),
        ]
        if let category {
            predicates.append(NSPredicate(format: "kind IN %@", category.kinds.map(\.rawValue)))
        }
        _events = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
            animation: .default
        )
        _editor = editor
        _toast = toast
        self.loadMore = loadMore
    }

    private var sections: [(day: Date, events: [Event])] {
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate ?? .distantPast) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.day) { section in
                Section {
                    ForEach(section.events) { event in
                        Button {
                            editor = EditorRoute(kind: event.eventKind, existing: event)
                        } label: {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if canEdit {
                                Button(role: .destructive) {
                                    let record = event.record
                                    let alarm = TimerAlarms.shared.duration(for: record.id)
                                    store.delete(event)
                                    toast = UndoToast(message: String(localized: "Entry deleted")) {
                                        store.save(record)
                                        if let alarm, record.isOngoing { TimerAlarms.shared.setDuration(alarm, for: record.id) }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    DayHeader(day: section.day, records: section.events.map(\.record))
                }
            }
            if !events.isEmpty {
                Button("Show Earlier Entries", action: loadMore)
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        // Shown over the empty list (not as a row) so it sits in the middle of the
        // screen instead of as a card at the top with blank space below it.
        .overlay {
            if events.isEmpty {
                // Older entries may still exist beyond the days shown, so the way to
                // them stays on screen.
                ContentUnavailableView {
                    if isFiltered {
                        Label("No Matching Entries", systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        Label("No Entries Yet", systemImage: "tray")
                    }
                } description: {
                    if isFiltered {
                        Text("Nothing of this kind in the days shown.")
                    } else {
                        Text("Entries you log will appear here.")
                    }
                } actions: {
                    Button("Show Earlier Entries", action: loadMore)
                }
            }
        }
    }
}

/// The day title with that day's totals. Each total keeps its icon and number
/// together; when they don't fit beside the title they move to a line below it.
private struct DayHeader: View {
    var day: Date
    var records: [EventRecord]

    var body: some View {
        let sleep = records.filter { $0.kind == .sleep }.reduce(0) { $0 + $1.duration(at: AppClock.now) }
        let feeds = records.filter { $0.kind.isFeeding }.count
        let diapers = records.filter { $0.kind == .diaper }.count
        let fussy = records.filter { $0.kind == .fussy }.count
        let totals = HStack(spacing: 10) {
            if sleep > 0 { total(.sleep, Fmt.duration(sleep)) }
            if feeds > 0 { total(.bottle, "\(feeds)") }
            if diapers > 0 { total(.diaper, "\(diapers)") }
            if fussy > 0 { total(.fussy, "\(fussy)") }
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary(sleep: sleep, feeds: feeds, diapers: diapers, fussy: fussy)))

        ViewThatFits(in: .horizontal) {
            HStack {
                Text(Fmt.dayTitle(day))
                Spacer()
                totals
            }
            // Below the date, wrapping onto more lines at large text sizes.
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.dayTitle(day))
                FlowLayout(spacing: 10, lineSpacing: 4) {
                    if sleep > 0 { total(.sleep, Fmt.duration(sleep)) }
                    if feeds > 0 { total(.bottle, "\(feeds)") }
                    if diapers > 0 { total(.diaper, "\(diapers)") }
                    if fussy > 0 { total(.fussy, "\(fussy)") }
                }
                .textCase(nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilitySummary(sleep: sleep, feeds: feeds, diapers: diapers, fussy: fussy)))
            }
        }
    }

    private func total(_ kind: EventKind, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: kind.systemImage).foregroundStyle(kind.color)
            Text(value).monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func accessibilitySummary(sleep: TimeInterval, feeds: Int, diapers: Int, fussy: Int) -> String {
        var parts: [String] = []
        if sleep > 0 { parts.append(String(localized: "Sleep \(Fmt.duration(sleep))")) }
        // Passed as text so the keys are "Feeds %@" / "Diapers %@" (an Int would
        // look up "%lld" and miss the translations).
        if feeds > 0 { parts.append(String(localized: "Feeds \(String(feeds))")) }
        if diapers > 0 { parts.append(String(localized: "Diapers \(String(diapers))")) }
        if fussy > 0 { parts.append(String(localized: "Fussy \(String(fussy))")) }
        return parts.joined(separator: ", ")
    }
}
