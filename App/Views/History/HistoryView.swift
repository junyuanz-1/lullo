import BabyCore
import CoreData
import SwiftUI

struct HistoryView: View {
    @ObservedObject var baby: Baby
    @State private var category: EventCategory?
    @State private var days = 14
    @State private var editor: EditorRoute?

    var body: some View {
        NavigationStack {
            HistoryList(baby: baby, category: category, days: days, editor: $editor) {
                days += 14
            }
            .navigationTitle("Log")
            .safeAreaInset(edge: .top) {
                CategoryFilter(selection: $category)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(EventKind.allCases) { kind in
                            Button {
                                editor = EditorRoute(kind: kind)
                            } label: {
                                Label(kind.title, systemImage: kind.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel(Text("Add entry"))
                }
            }
            .sheet(item: $editor) { route in
                NavigationStack {
                    EventEditorView(baby: baby, kind: route.kind, existing: route.existing)
                }
            }
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
                .background(selected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryList: View {
    @EnvironmentObject private var store: TrackerStore
    @FetchRequest private var events: FetchedResults<Event>
    @Binding var editor: EditorRoute?
    var loadMore: () -> Void

    init(baby: Baby, category: EventCategory?, days: Int, editor: Binding<EditorRoute?>, loadMore: @escaping () -> Void) {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date()))!
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
        self.loadMore = loadMore
    }

    private var sections: [(day: Date, events: [Event])] {
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate ?? .distantPast) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView("No entries yet", systemImage: "tray", description: Text("Entries you log will appear here."))
            }
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
                            Button(role: .destructive) {
                                store.delete(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(Fmt.dayTitle(section.day))
                        Spacer()
                        Text(daySummary(section.events)).textCase(nil)
                    }
                }
            }
            if !events.isEmpty {
                Button("Show earlier entries", action: loadMore)
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func daySummary(_ events: [Event]) -> String {
        let records = events.map(\.record)
        let feeds = records.filter { $0.kind.isFeeding }.count
        let diapers = records.filter { $0.kind == .diaper }.count
        let sleep = records.filter { $0.kind == .sleep }.reduce(0) { $0 + $1.duration() }
        var parts: [String] = []
        if sleep > 0 { parts.append("💤 \(Fmt.duration(sleep))") }
        if feeds > 0 { parts.append("🍼 \(feeds)") }
        if diapers > 0 { parts.append("🧷 \(diapers)") }
        return parts.joined(separator: "  ")
    }
}
