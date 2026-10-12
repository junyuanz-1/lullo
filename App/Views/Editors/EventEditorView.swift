import BabyCore
import CoreData
import SwiftUI

/// Create or edit any kind of entry. Timer kinds can either start a live timer
/// or be logged after the fact.
struct EventEditorView: View {
    enum Mode: Hashable { case timer, manual }

    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var baby: Baby
    let existing: Event?
    @State private var draft: EventRecord
    /// The stored version `draft` was last reconciled with; see `syncWithStore`.
    @State private var baseline: EventRecord?
    @State private var mode: Mode
    @State private var medicationReminderHours: Double = 0
    @State private var timerStart = AppClock.now
    @State private var confirmingDelete = false
    @State private var closing = false
    @State private var newTimerAlarm: Int?
    @ObservedObject private var alarms = TimerAlarms.shared

    /// - Parameter mode: timer or "log past" for a new entry; nil picks the
    ///   default (timer for kinds that support one).
    init(baby: Baby, kind: EventKind, existing: Event?, mode: Mode? = nil) {
        self.baby = baby
        self.existing = existing
        let now = AppClock.now
        var record = existing?.record ?? EventRecord(babyID: baby.id ?? UUID(), kind: kind, startDate: now)
        if existing == nil {
            let lastOfKind = TrackerStore.shared.lastEvent(of: [kind], for: baby)?.record
            Self.applyDefaults(to: &record, now: now, lastOfKind: lastOfKind)
        }
        _draft = State(initialValue: record)
        _baseline = State(initialValue: existing?.record)
        _newTimerAlarm = State(initialValue: TimerAlarms.shared.lastUsed(for: kind).map { Int($0 / 60) })
        _mode = State(initialValue: mode ?? (existing == nil && kind.supportsTimer ? .timer : .manual))
    }

    private var isNew: Bool { existing == nil }
    private var kind: EventKind { draft.kind }
    private var canEdit: Bool { store.persistence.canEdit(baby) }

    var body: some View {
        Form {
            // Read-only caregivers can look but not change; Cancel in the
            // toolbar stays enabled so the sheet can still be closed.
            Group { formContent }
                .disabled(!canEdit)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if !(mode == .timer && isNew) {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid || !canEdit)
                }
            }
        }
        .listSectionSpacing(.compact)
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                closing = true
                if let existing { store.delete(existing) }
                dismiss()
            }
        }
        // The entry can change while it is open: stopped from the Lock Screen or a
        // widget, or edited by a caregiver on another device.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: store.context)) { note in
            syncWithStore(note)
        }
    }

    @ViewBuilder
    private var formContent: some View {
        if isNew && kind.supportsTimer {
            Section {
                PillSegmentedControl<Mode>(
                    segments: [
                        .init(value: Mode.timer, title: String(localized: "Timer"), systemImage: "timer"),
                        .init(value: Mode.manual, title: String(localized: "Log Past"), systemImage: "clock.arrow.circlepath"),
                    ],
                    selection: $mode,
                    tint: kind.color
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }

        if mode == .timer && isNew {
            timerStartSection
        } else {
            timeSection
        }

        detailSections

        Section("Notes") {
            TextField("Add a note", text: Binding(
                get: { draft.note ?? "" },
                set: { draft.note = $0 }
            ), axis: .vertical)
            .lineLimit(1...5)
            PhotoField(title: String(localized: "Add Photo"), data: $draft.photoData)
        }

        if !isNew {
            Section {
                if let author = draft.authorName {
                    LabeledContent("Logged By", value: author)
                }
                Button("Delete Entry", role: .destructive) { confirmingDelete = true }
            }
        }
    }

    /// Pulls in changes made to the stored entry since the editor opened, keeping
    /// whatever the user has edited here.
    private func syncWithStore(_ note: Notification) {
        guard !closing, let existing, let base = baseline else { return }
        let removed = [NSDeletedObjectsKey, NSInvalidatedObjectsKey].contains { key in
            (note.userInfo?[key] as? Set<NSManagedObject>)?.contains(existing) == true
        }
        if removed || existing.isDeleted || existing.managedObjectContext == nil {
            closing = true
            dismiss()
            return
        }
        let latest = existing.record
        guard latest != base else { return }
        draft = draft.rebased(onto: latest, from: base)
        baseline = latest
    }

    // MARK: Time

    @ViewBuilder
    private var timerStartSection: some View {
        if kind != .nursing {
            Section {
                if kind == .activity {
                    activityTypePicker
                }
                DatePicker("Start", selection: $timerStart, in: ...AppClock.now)
            }
        }
        if TimerAlarm.supportedKinds.contains(kind) {
            Section {
                alarmPicker(selection: $newTimerAlarm)
            } footer: {
                Text("Rings with a gentle sound. Choose the sound in More → Timer Alarm.")
            }
        }
        // The start buttons get their own section with no card behind them, so
        // the cards above keep their rounded bottoms instead of looking cut off.
        Section {
            if kind == .nursing {
                let suggested = EventRecord.suggestedNextSide(after: store.lastEvent(of: [.nursing], for: baby)?.record)
                HStack(spacing: 16) {
                    ForEach([BreastSide.left, .right], id: \.self) { side in
                        Button {
                            startNursing(side)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.title2)
                                Text("Start \(side.title)").font(.headline)
                                // Always laid out so both buttons are the same height.
                                Text("Suggested").font(.caption2.bold())
                                    .opacity(side == suggested ? 1 : 0)
                                    .accessibilityHidden(side != suggested)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(side == suggested ? Color.pink : Color.pink.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(side == suggested ? .white : .pink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button {
                    startTimer()
                } label: {
                    Label("Start Timer", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(kind.color)
            }
        } footer: {
            Text("The timer keeps running on your Lock Screen and Dynamic Island.")
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// Countdown choices ("ring after 10 min"). Nursing counts each side separately.
    private func alarmPicker(selection: Binding<Int?>) -> some View {
        ChipPicker(
            title: kind == .nursing ? String(localized: "Alarm per Side") : String(localized: "Alarm"),
            options: TimerAlarm.presetMinutes(for: kind),
            selection: selection,
            tint: kind.color,
            label: { Fmt.duration(TimeInterval($0 * 60), style: .short) },
            systemImage: { _ in "bell.fill" }
        )
    }

    @ViewBuilder
    private var timeSection: some View {
        Section {
            if kind == .nursing && draft.isOngoing && !isNew {
                // A running session: the start can be corrected ("it actually began
                // earlier"), the side times keep counting. The timer card has the
                // controls and the alarm.
                DatePicker("Start", selection: $draft.startDate, in: ...Date())
                ForEach(BreastSide.allCases, id: \.self) { side in
                    ClockTimeline(every: 1) { now in
                        LabeledContent(side.title, value: Fmt.duration(draft.nursingElapsed(side, at: now)))
                    }
                }
                Button("Stop Now") {
                    if let existing { store.stopTimer(existing) }
                }
            } else if kind == .nursing {
                DatePicker("Start", selection: $draft.startDate)
                minutesField(BreastSide.left.title, value: $draft.leftDuration)
                minutesField(BreastSide.right.title, value: $draft.rightDuration)
                // Which side to suggest next only needs asking when both were used.
                if draft.leftDuration > 0 && draft.rightDuration > 0 {
                    ChipPicker(title: String(localized: "Ended On"), options: BreastSide.allCases, selection: $draft.lastSide, tint: .pink, label: \.title)
                }
            } else {
                DatePicker(kind.hasDuration ? String(localized: "Start") : String(localized: "Time"), selection: $draft.startDate)
            }
            if kind != .nursing && kind.hasDuration {
                if draft.endDate == nil && !isNew {
                    LabeledContent("End", value: String(localized: "Running"))
                    Button("Stop Now") {
                        // Stops the stored timer right away (and its Live Activity);
                        // the end time then shows up here through syncWithStore.
                        if let existing { store.stopTimer(existing) } else { draft.endDate = Date() }
                    }
                    ClockTimeline(every: 1) { now in
                        LabeledContent("Duration", value: Fmt.duration(draft.duration(at: now)))
                    }
                } else {
                    DatePicker("End", selection: Binding(
                        get: { draft.endDate ?? draft.startDate },
                        set: { draft.endDate = $0 }
                    ), in: draft.startDate...)
                    LabeledContent("Duration", value: Fmt.duration(draft.duration()))
                }
            }
        }
    }

    /// One row per side: type the minutes, or nudge them with the stepper.
    private func minutesField(_ title: String, value: Binding<TimeInterval>) -> some View {
        let minutes = Binding<Int>(
            get: { Int((value.wrappedValue / 60).rounded()) },
            set: { value.wrappedValue = TimeInterval(max(0, min(180, $0)) * 60) }
        )
        let placeholder = "0"
        return HStack(spacing: 8) {
            Text(title)
            Spacer()
            TextField(placeholder, value: minutes, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text("min").foregroundStyle(.secondary)
            Stepper(title, value: minutes, in: 0...180)
                .labelsHidden()
        }
    }

    // MARK: Kind-specific fields

    @ViewBuilder
    private var detailSections: some View {
        switch kind {
        case .sleep:
            Section("Details") {
                ChipPicker(title: String(localized: "Where"), options: SleepLocation.allCases, selection: $draft.sleepLocation, tint: .indigo, label: \.title)
            }
        case .nursing:
            EmptyView()
        case .bottle:
            Section {
                MeasurementField(title: String(localized: "Amount"), metricValue: $draft.amountML, quantity: .volume)
                VolumePresets(metricValue: $draft.amountML)
                ChipPicker(title: String(localized: "Contents"), options: BottleContent.allCases, selection: $draft.bottleContent, tint: .orange, label: \.title)
            }
        case .solids:
            Section("Food") {
                TextField("What did they eat?", text: optionalText($draft.foodName))
                MeasurementField(title: String(localized: "Amount"), metricValue: $draft.amountML, quantity: .volume)
                ChipPicker(title: String(localized: "Reaction"), options: FoodReaction.allCases, selection: $draft.foodReaction, tint: EventKind.solids.color) {
                    "\($0.emoji) \($0.title)"
                }
            }
            if draft.foodReaction == .allergic {
                Section {
                    Label("Watch for hives, swelling, vomiting or trouble breathing. Call emergency services if breathing is affected.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        case .pumping:
            Section("Amount") {
                MeasurementField(title: String(localized: "Left"), metricValue: $draft.leftAmountML, quantity: .volume)
                MeasurementField(title: String(localized: "Right"), metricValue: $draft.rightAmountML, quantity: .volume)
                if let total = draft.pumpedTotalML, draft.leftAmountML != nil || draft.rightAmountML != nil {
                    LabeledContent("Total", value: Fmt.volume(total))
                }
            }
        case .diaper:
            diaperSections
        case .growth:
            growthSection
        case .medication:
            Section("Medication") {
                TextField("Name", text: optionalText($draft.medicationName))
                TextField("Dose (e.g. 2.5 ml)", text: optionalText($draft.dosage))
                if isNew {
                    ChipPicker(
                        title: String(localized: "Remind Next Dose"),
                        options: [0.0, 4, 6, 8, 12, 24],
                        value: $medicationReminderHours,
                        tint: EventKind.medication.color
                    ) { hours in
                        hours == 0 ? String(localized: "Off") : String(localized: "In \(Fmt.duration(hours * 3600, style: .full))")
                    }
                }
            }
        case .temperature:
            Section("Temperature") {
                MeasurementField(title: String(localized: "Temperature"), metricValue: $draft.temperatureC, quantity: .temperature)
            }
            if let c = draft.temperatureC, c >= 38 {
                Section {
                    Label(feverAdvice, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        case .symptom:
            Section("Symptoms") {
                TextField("e.g. cough, runny nose, rash", text: optionalText($draft.symptoms), axis: .vertical)
                    .lineLimit(1...4)
            }
        case .vaccine:
            Section("Vaccine") {
                TextField("Vaccine name", text: optionalText($draft.vaccineName))
            }
        case .activity:
            if mode == .manual || !isNew {
                Section("Activity") { activityTypePicker }
            }
        case .note:
            EmptyView()
        }
    }

    private var activityTypePicker: some View {
        ChipPicker(
            title: String(localized: "Type"),
            options: ActivityType.allCases,
            selection: $draft.activityType,
            allowsDeselect: false,
            tint: EventKind.activity.color,
            label: \.title,
            systemImage: { $0.systemImage }
        )
    }

    @ViewBuilder
    private var diaperSections: some View {
        Section("Type") {
            HStack(spacing: 10) {
                ForEach(DiaperType.allCases, id: \.self) { type in
                    let selected = draft.diaperType == type
                    Button {
                        draft.diaperType = type
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.systemImage).font(.title3)
                            Text(type.title).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Color.teal : Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(selected ? .white : .teal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
        }
        if draft.diaperType?.isWet == true {
            Section("Pee Amount") {
                ChipPicker(title: nil, options: PeeAmount.allCases, selection: $draft.peeAmount, tint: .teal, label: \.title)
            }
        }
        if draft.diaperType?.isDirty == true {
            Section("Poop") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(PoopColor.allCases, id: \.self) { color in
                            Button {
                                draft.poopColor = draft.poopColor == color ? nil : color
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(color.swatch)
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(draft.poopColor == color ? Color.accentColor : .secondary.opacity(0.3), lineWidth: draft.poopColor == color ? 3 : 1))
                                    Text(color.title).font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                ChipPicker(title: String(localized: "Consistency"), options: PoopConsistency.allCases, selection: $draft.poopConsistency, tint: .brown, label: \.title)
                if draft.poopColor?.needsAttention == true {
                    Label("Black (after the first days), red or pale/white stool can be a sign of a problem. Consider calling your pediatrician.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        Section {
            Toggle("Diaper Rash", isOn: $draft.hasRash)
        }
    }

    @ViewBuilder
    private var growthSection: some View {
        let record = baby.record
        let age = record.ageInMonths(at: draft.startDate)
        Section("Measurements") {
            MeasurementField(title: String(localized: "Weight"), metricValue: $draft.weightKg, quantity: .weight)
            MeasurementField(title: String(localized: "Length"), metricValue: $draft.heightCm, quantity: .length)
            MeasurementField(title: String(localized: "Head"), metricValue: $draft.headCm, quantity: .length)
        }
        if record.sex != .unspecified {
            Section("WHO Percentiles") {
                ForEach(GrowthMetric.allCases) { metric in
                    if let value = metric.value(of: draft),
                       let p = GrowthStandards.percentile(of: value, metric: metric, sex: record.sex, ageInMonths: age) {
                        LabeledContent(metric.title, value: Fmt.percentile(p))
                    }
                }
            }
        }
    }

    private var feverAdvice: String {
        let ageMonths = baby.record.ageInMonths(at: draft.startDate)
        if ageMonths < 3 {
            return String(localized: "A temperature of 38 °C (100.4 °F) or higher in a baby under 3 months needs prompt medical attention. Call your doctor now.")
        }
        return String(localized: "This is a fever. Call your doctor if your baby seems unwell, the fever lasts more than a day, or you are worried.")
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0 })
    }

    // MARK: Actions

    private var isValid: Bool {
        switch kind {
        case .diaper: return draft.diaperType != nil
        case .growth: return draft.weightKg != nil || draft.heightCm != nil || draft.headCm != nil
        case .medication: return draft.medicationName?.nilIfBlank != nil
        case .temperature: return draft.temperatureC != nil
        case .nursing: return draft.leftDuration + draft.rightDuration > 0 || draft.isOngoing
        default:
            if kind.hasDuration, let end = draft.endDate { return end >= draft.startDate }
            return true
        }
    }

    private func startTimer() {
        let event: Event?
        if kind == .activity {
            event = store.startTimer(.activity, for: baby, activityType: draft.activityType ?? .play, at: timerStart)
        } else {
            event = store.startTimer(kind, for: baby, at: timerStart)
        }
        applyDraftDetails(to: event)
        applyNewTimerAlarm(to: event)
        dismiss()
    }

    private func startNursing(_ side: BreastSide) {
        let event = store.startNursing(for: baby, side: side)
        applyDraftDetails(to: event)
        applyNewTimerAlarm(to: event)
        dismiss()
    }

    /// Carries over what was filled in before tapping Start (sleep location,
    /// pumped amounts, note, photo) so it is not silently lost.
    private func applyDraftDetails(to event: Event?) {
        guard let event else { return }
        var record = event.record
        if let location = draft.sleepLocation { record.sleepLocation = location }
        if let amount = draft.amountML { record.amountML = amount }
        if let contents = draft.bottleContent { record.bottleContent = contents }
        if let left = draft.leftAmountML { record.leftAmountML = left }
        if let right = draft.rightAmountML { record.rightAmountML = right }
        if let note = draft.note?.nilIfBlank { record.note = note }
        if let photo = draft.photoData { record.photoData = photo }
        if record != event.record { store.save(record) }
    }

    private func applyNewTimerAlarm(to event: Event?) {
        let duration = newTimerAlarm.map { TimeInterval($0 * 60) }
        alarms.rememberLastUsed(duration, for: kind)
        if let id = event?.id, let duration { alarms.setDuration(duration, for: id) }
    }

    private func save() {
        closing = true
        var record = draft
        if record.diaperType?.isWet != true { record.peeAmount = nil }
        if kind == .nursing, !isNew, record.isOngoing, let base = baseline, record.startDate != base.startDate {
            // Moving the start of a running session moves the time already
            // counted with it: 10 minutes earlier means 10 more minutes nursed.
            let delta = record.startDate.timeIntervalSince(base.startDate)
            if let since = record.activeSideStartedAt {
                record.activeSideStartedAt = min(Date(), since.addingTimeInterval(delta))
            } else if let side = record.lastSide {
                switch side {
                case .left: record.leftDuration = max(0, record.leftDuration - delta)
                case .right: record.rightDuration = max(0, record.rightDuration - delta)
                }
            }
        }
        if isNew && kind.hasDuration {
            if kind == .nursing {
                record.activeSide = nil
                record.activeSideStartedAt = nil
                if record.leftDuration > 0 && record.rightDuration == 0 { record.lastSide = .left }
                if record.rightDuration > 0 && record.leftDuration == 0 { record.lastSide = .right }
                record.endDate = record.startDate.addingTimeInterval(record.leftDuration + record.rightDuration)
            } else if record.endDate == nil {
                record.endDate = record.startDate
            }
        }
        store.save(record)
        if kind == .medication, isNew, medicationReminderHours > 0, let name = record.medicationName {
            NotificationManager.scheduleMedicationReminder(
                eventID: record.id,
                babyName: baby.displayName,
                medication: name,
                at: record.startDate.addingTimeInterval(medicationReminderHours * 3600)
            )
        }
        dismiss()
    }

    /// Sensible defaults for a new entry, based on what was logged last.
    private static func applyDefaults(to record: inout EventRecord, now: Date, lastOfKind: EventRecord?) {
        switch record.kind {
        case .bottle:
            // Most bottles are the same as the last one: amount and contents are
            // prefilled so a repeat is just "Save".
            record.amountML = lastOfKind?.amountML
            record.bottleContent = lastOfKind?.bottleContent ?? .formula
        case .diaper:
            record.diaperType = .wet
        case .activity:
            record.activityType = .tummyTime
        default:
            break
        }
        if record.kind.hasDuration && record.kind != .nursing {
            // For "log past", default to a range ending now.
            let minutes: Double = record.kind == .bottle ? 15 : 30
            record.startDate = now.addingTimeInterval(-minutes * 60)
            record.endDate = now
        }
    }
}
