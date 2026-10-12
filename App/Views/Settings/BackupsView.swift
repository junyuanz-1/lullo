import BabyCore
import SwiftUI

/// Lists the automatic daily backups and restores one.
struct BackupsView: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject private var backups = AutoBackup.shared

    @State private var selected: AutoBackup.Entry?
    @State private var confirmingRestore: AutoBackup.Entry?
    @State private var sharing: ShareableFile?
    @State private var restoredFrom: Date?
    @State private var skippedSharedBabies = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    run { _ = try backups.backUp(store: store, reason: .manual) }
                } label: {
                    Label("Back Up Now", systemImage: "arrow.clockwise.icloud")
                }
            } footer: {
                Text("Tinytide backs up all babies and entries once a day and keeps the latest 10 on this iPhone. If something is changed or deleted by mistake, by you or anyone you share with, restore an earlier backup.")
            }

            Section("Backups") {
                if backups.entries.isEmpty {
                    Text("No backups yet. One is made automatically each day you open the app.")
                        .foregroundStyle(.secondary)
                }
                ForEach(backups.entries) { entry in
                    Button {
                        selected = entry
                    } label: {
                        BackupRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            backups.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Automatic Backups")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { backups.reload() }
        .confirmationDialog(
            selected.map { Fmt.backupDate($0.date) } ?? "",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible,
            presenting: selected
        ) { entry in
            Button("Restore This Backup") { confirmingRestore = entry }
            Button("Share Backup File") { sharing = ShareableFile(url: entry.url) }
            Button("Delete Backup", role: .destructive) { backups.delete(entry) }
        }
        .alert(
            "Restore Backup?",
            isPresented: Binding(get: { confirmingRestore != nil }, set: { if !$0 { confirmingRestore = nil } }),
            presenting: confirmingRestore
        ) { entry in
            Button("Restore", role: .destructive) { restore(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Everything goes back to how it was on \(Fmt.backupDate(entry.date)): entries added since then are removed, and changed or deleted entries come back. This also changes the data for everyone you share with. Your current data is backed up first, so you can undo this.")
        }
        .alert(
            "Restore Complete",
            isPresented: Binding(get: { restoredFrom != nil }, set: { if !$0 { restoredFrom = nil } }),
            presenting: restoredFrom
        ) { _ in
            Button("OK") {}
        } message: { date in
            if skippedSharedBabies {
                Text("Your data now matches the backup from \(Fmt.backupDate(date)). Babies shared with you as view-only were not changed.")
            } else {
                Text("Your data now matches the backup from \(Fmt.backupDate(date)).")
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func restore(_ entry: AutoBackup.Entry) {
        run {
            let summary = try backups.restore(entry, store: store)
            skippedSharedBabies = summary.skippedBabies > 0
            restoredFrom = entry.date
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BackupRow: View {
    let entry: AutoBackup.Entry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.backupDate(entry.date)).font(.body)
                Text(verbatim: "\(reasonTitle) · \(entry.size.formatted(.byteCount(style: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch entry.reason {
        case .daily: return "calendar"
        case .manual: return "hand.tap"
        case .beforeRestore: return "arrow.uturn.backward"
        }
    }

    private var reasonTitle: String {
        switch entry.reason {
        case .daily: return String(localized: "Daily")
        case .manual: return String(localized: "Manual")
        case .beforeRestore: return String(localized: "Before Restore")
        }
    }
}

extension Fmt {
    static func backupDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
