import BabyCore
import CloudKit
import CoreData
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: TrackerStore
    @EnvironmentObject private var sync: SyncMonitor
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)])
    private var babies: FetchedResults<Baby>

    @AppStorage(SettingsKey.unitSystem, store: SharedContainer.defaults) private var unitSystem: UnitSystem = AppSettings.unitSystem
    @AppStorage(SettingsKey.temperatureUnit, store: SharedContainer.defaults) private var temperatureUnit: TemperatureUnit = AppSettings.temperatureUnit
    @AppStorage(SettingsKey.nightStartHour, store: SharedContainer.defaults) private var nightStartHour = 19
    @AppStorage(SettingsKey.nightEndHour, store: SharedContainer.defaults) private var nightEndHour = 6
    @AppStorage(SettingsKey.caregiverName, store: SharedContainer.defaults) private var caregiverName = ""
    @AppStorage(SettingsKey.feedReminderEnabled, store: SharedContainer.defaults) private var feedReminder = false
    @AppStorage(SettingsKey.feedReminderHours, store: SharedContainer.defaults) private var feedHours = 3.0
    @AppStorage(SettingsKey.diaperReminderEnabled, store: SharedContainer.defaults) private var diaperReminder = false
    @AppStorage(SettingsKey.diaperReminderHours, store: SharedContainer.defaults) private var diaperHours = 3.0
    @AppStorage(SettingsKey.napReminderEnabled, store: SharedContainer.defaults) private var napReminder = false
    @AppStorage(SettingsKey.liveActivitiesEnabled, store: SharedContainer.defaults) private var liveActivities = true

    @State private var editingBaby: Baby?
    @State private var addingBaby = false
    @State private var sharingBaby: Baby?
    @State private var shareError: String?

    @State private var exportFile: ShareableFile?
    @State private var importing = false
    @State private var pendingImport: BackupFile?
    @State private var importResult: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                babiesSection
                familySection
                preferencesSection
                remindersSection
                iCloudSection
                dataSection
                supportSection
                aboutSection
            }
            .navigationTitle("More")
            .sheet(item: $editingBaby) { baby in
                NavigationStack { BabyFormView(baby: baby) }
            }
            .sheet(isPresented: $addingBaby) {
                NavigationStack { BabyFormView(baby: nil) }
            }
            .sheet(item: $exportFile) { file in
                ActivityShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                handleImportSelection(result)
            }
            .alert("Import backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
                Button("Import") {
                    if let file = pendingImport { runImport(file) }
                    pendingImport = nil
                }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                if let file = pendingImport {
                    Text("The file contains \(String(file.babies.count)) babies and \(String(file.events.count)) entries. Entries you already have are kept; newer copies replace older ones.")
                }
            }
            .alert("Import finished", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {
                Button("OK") { importResult = nil }
            } message: {
                Text(importResult ?? "")
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var babiesSection: some View {
        Section("Babies") {
            ForEach(babies) { baby in
                Button {
                    editingBaby = baby
                } label: {
                    HStack {
                        BabyAvatar(photoData: baby.photoData, name: baby.displayName, size: 36)
                        VStack(alignment: .leading) {
                            Text(baby.displayName).foregroundStyle(.primary)
                            Text(Fmt.age(birthDate: baby.birthDate ?? Date())).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.persistence.isParticipant(baby) {
                            Text("Shared with you").font(.caption).foregroundStyle(.blue)
                        } else if baby.id == store.selectedBabyID || (store.selectedBabyID == nil && baby == babies.first) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            Button {
                addingBaby = true
            } label: {
                Label("Add Baby", systemImage: "plus")
            }
        }
    }

    private var familySection: some View {
        Section {
            TextField("Your name (shown on entries)", text: $caregiverName)
                .textContentType(.givenName)
            ForEach(babies) { baby in
                Button {
                    share(baby)
                } label: {
                    HStack {
                        Label {
                            Text(store.persistence.isShared(baby)
                                 ? String(localized: "Manage sharing for \(baby.displayName)")
                                 : String(localized: "Share \(baby.displayName)"))
                        } icon: {
                            Image(systemName: store.persistence.isShared(baby) ? "person.2.fill" : "person.badge.plus")
                        }
                        Spacer()
                        if sharingBaby == baby { ProgressView() }
                    }
                }
                .disabled(sharingBaby != nil)
            }
        } header: {
            Text("Family & Caregivers")
        } footer: {
            Text("Invite a partner, grandparent or nanny with their Apple ID. Everyone sees and logs the same data in real time. Invitees open the link on their iPhone with this app installed.")
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Picker("Units", selection: $unitSystem) {
                ForEach(UnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Temperature", selection: $temperatureUnit) {
                ForEach(TemperatureUnit.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Night starts", selection: $nightStartHour) {
                ForEach(17..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
            }
            Picker("Night ends", selection: $nightEndHour) {
                ForEach(3..<11, id: \.self) { Text(hourLabel($0)).tag($0) }
            }
            Toggle("Live Activities", isOn: $liveActivities)
                .onChange(of: liveActivities) { _, enabled in
                    if !enabled { LiveActivityManager.shared.endAll() }
                    store.refreshSideEffects()
                }
        }
        .onChange(of: unitSystem) { _, _ in store.refreshSideEffects() }
        .onChange(of: nightStartHour) { _, _ in store.refreshSideEffects() }
        .onChange(of: nightEndHour) { _, _ in store.refreshSideEffects() }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Feeding reminder", isOn: $feedReminder)
            if feedReminder {
                Stepper(value: $feedHours, in: 1...6, step: 0.5) {
                    LabeledContent("After last feed", value: Fmt.duration(feedHours * 3600))
                }
            }
            Toggle("Diaper reminder", isOn: $diaperReminder)
            if diaperReminder {
                Stepper(value: $diaperHours, in: 1...6, step: 0.5) {
                    LabeledContent("After last change", value: Fmt.duration(diaperHours * 3600))
                }
            }
            Toggle("Nap sweet spot reminder", isOn: $napReminder)
        } header: {
            Text("Reminders")
        } footer: {
            Text("Medication reminders can be set when logging a dose.")
        }
        .onChange(of: feedReminder) { _, on in remindersChanged(on) }
        .onChange(of: diaperReminder) { _, on in remindersChanged(on) }
        .onChange(of: napReminder) { _, on in remindersChanged(on) }
        .onChange(of: feedHours) { _, _ in store.refreshSideEffects() }
        .onChange(of: diaperHours) { _, _ in store.refreshSideEffects() }
    }

    private var iCloudSection: some View {
        Section {
            LabeledContent("iCloud account", value: accountText)
            if let lastSync = sync.lastSync {
                LabeledContent("Last synced", value: lastSync.formatted(date: .abbreviated, time: .shortened))
            } else if sync.isSyncing {
                LabeledContent("Status", value: String(localized: "Syncing…"))
            }
            if let error = sync.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text("Your data is stored in your private iCloud database and backed up automatically. On a new iPhone, sign in with the same Apple ID and install the app: everything downloads automatically.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                export { try BackupService.exportBackup(store: store) }
            } label: {
                Label("Export Backup File", systemImage: "square.and.arrow.up")
            }
            Button {
                export { try BackupService.exportCSV(store: store) }
            } label: {
                Label("Export Spreadsheet (CSV)", systemImage: "tablecells")
            }
            Button {
                importing = true
            } label: {
                Label("Import Backup File", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup & Transfer")
        } footer: {
            Text("A backup file contains all babies and entries. Save it to Files or iCloud Drive, or AirDrop it to another phone and import it there, including a phone that uses a different Apple ID.")
        }
    }

    private var supportSection: some View {
        Section {
            NavigationLink {
                TipJarView()
            } label: {
                Label {
                    Text("Support Lullo")
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
            }
        } footer: {
            Text("Optional tips help keep Lullo independent and ad-free.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            Text("Sleep predictions, growth percentiles and alerts are general guidance, not medical advice. Always consult your pediatrician about your baby's health.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Growth charts use the WHO Child Growth Standards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var accountText: String {
        switch sync.account {
        case .available: return String(localized: "Signed in")
        case .noAccount: return String(localized: "Not signed in")
        case .restricted: return String(localized: "Restricted")
        case .temporarilyUnavailable: return String(localized: "Temporarily unavailable")
        case .unknown: return String(localized: "Checking…")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func remindersChanged(_ enabled: Bool) {
        Task {
            if enabled { _ = await NotificationManager.requestAuthorization() }
            store.refreshSideEffects()
        }
    }

    private func export(_ make: () throws -> URL) {
        do {
            exportFile = ShareableFile(url: try make())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            pendingImport = try BackupService.readBackup(at: result.get())
        } catch BackupError.unsupportedVersion {
            errorMessage = String(localized: "This backup was made by a newer version of the app. Please update first.")
        } catch {
            errorMessage = String(localized: "This file is not a valid backup.")
        }
    }

    private func runImport(_ file: BackupFile) {
        let summary = BackupService.importBackup(file, into: store)
        importResult = String(localized: "Added \(String(summary.babiesAdded)) babies and \(String(summary.eventsAdded)) entries, updated \(String(summary.eventsUpdated + summary.babiesUpdated)), skipped \(String(summary.eventsSkipped)).")
    }

    private func share(_ baby: Baby) {
        sharingBaby = baby
        Task {
            defer { sharingBaby = nil }
            do {
                let share = try await store.persistence.share(baby)
                CloudSharingPresenter.present(share: share, baby: baby, persistence: store.persistence)
            } catch {
                errorMessage = String(localized: "Could not start sharing. Make sure you are signed in to iCloud. (\(error.localizedDescription))")
            }
        }
    }
}
