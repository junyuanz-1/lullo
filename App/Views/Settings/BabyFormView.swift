import BabyCore
import SwiftUI

/// Create or edit a baby profile.
struct BabyFormView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    let baby: Baby?
    @State private var record: BabyRecord
    @State private var confirmingDelete = false

    init(baby: Baby?) {
        self.baby = baby
        _record = State(initialValue: baby?.record ?? BabyRecord(name: "", birthDate: Calendar.current.startOfDay(for: Date())))
    }

    private var canEdit: Bool { baby.map { store.persistence.canEdit($0) } ?? true }
    private var isParticipant: Bool { baby.map { store.persistence.isParticipant($0) } ?? false }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    BabyAvatar(photoData: record.photoData, name: record.name.isEmpty ? "?" : record.name, size: 96)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                PhotoField(title: String(localized: "Choose photo"), data: $record.photoData)
            }
            Section {
                TextField("Name", text: $record.name)
                    .textContentType(.name)
                DatePicker("Birthday", selection: $record.birthDate, in: ...Date().addingTimeInterval(270 * 86_400), displayedComponents: [.date, .hourAndMinute])
                Picker("Sex", selection: $record.sex) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Sex is used for WHO growth percentiles.")
            }
            .disabled(!canEdit)

            if baby != nil && !isParticipant {
                Section {
                    Button("Delete Baby and All Entries", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(baby == nil ? Text("New Baby") : Text("Edit Baby"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(record.name.trimmingCharacters(in: .whitespaces).isEmpty || !canEdit)
            }
        }
        .confirmationDialog("Delete this baby?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let baby { store.deleteBaby(baby) }
                dismiss()
            }
        } message: {
            Text("All entries for this baby will be deleted from every device and from anyone you shared with. This cannot be undone.")
        }
    }

    private func save() {
        record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let baby {
            store.updateBaby(baby, with: record)
        } else {
            store.addBaby(record)
        }
        dismiss()
    }
}
