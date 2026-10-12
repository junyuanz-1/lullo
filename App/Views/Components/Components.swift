import BabyCore
import PhotosUI
import SwiftUI
import TipKit
import UIKit

struct BabyAvatar: View {
    var photoData: Data?
    var name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.pink.opacity(0.6), .orange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Rounded card used throughout the home and trends screens.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(tint) }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct KindIcon: View {
    var systemImage: String
    var color: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Number field that edits a metric value while showing the user's units.
/// The unit can be switched inline; the choice is saved as the app-wide setting.
struct MeasurementField: View {
    enum Quantity {
        case volume, weight, length, temperature
    }

    var title: String
    @Binding var metricValue: Double?
    var quantity: Quantity

    @AppStorage(SettingsKey.unitSystem, store: SharedContainer.defaults) private var unitSystem: UnitSystem = AppSettings.unitSystem
    @AppStorage(SettingsKey.temperatureUnit, store: SharedContainer.defaults) private var temperatureUnit: TemperatureUnit = AppSettings.temperatureUnit

    private var displayBinding: Binding<Double?> {
        Binding(
            get: { metricValue.map(toDisplay) },
            set: { metricValue = $0.map(toMetric) }
        )
    }

    private func toDisplay(_ v: Double) -> Double {
        let converted: Double
        switch quantity {
        case .volume: converted = unitSystem == .metric ? v : UnitConversion.ounces(fromML: v)
        case .weight: converted = unitSystem == .metric ? v : UnitConversion.pounds(fromKg: v)
        case .length: converted = unitSystem == .metric ? v : UnitConversion.inches(fromCm: v)
        case .temperature: converted = temperatureUnit == .celsius ? v : UnitConversion.fahrenheit(fromCelsius: v)
        }
        return (converted * 100).rounded() / 100
    }

    private func toMetric(_ v: Double) -> Double {
        switch quantity {
        case .volume: return unitSystem == .metric ? v : UnitConversion.ml(fromOunces: v)
        case .weight: return unitSystem == .metric ? v : UnitConversion.kg(fromPounds: v)
        case .length: return unitSystem == .metric ? v : UnitConversion.cm(fromInches: v)
        case .temperature: return temperatureUnit == .celsius ? v : UnitConversion.celsius(fromFahrenheit: v)
        }
    }

    /// What's in the field. Parsed on every keystroke (a value-based TextField
    /// only commits on Return, which the decimal pad doesn't have, so a number
    /// typed just before Save was lost) and in the user's locale ("3,5").
    @State private var text = ""

    var body: some View {
        let placeholder = "0"
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            unitToggle
        }
        .onAppear { text = formatted(metricValue) }
        .onChange(of: text) { _, newText in
            // Reformatting after a unit switch isn't an edit: rounding the shown
            // value back into metric would nudge it.
            guard newText != formatted(metricValue) else { return }
            displayBinding.wrappedValue = Self.parse(newText)
        }
        // Set from elsewhere (a preset, a unit switch): show it, unless the
        // field already says the same thing.
        .onChange(of: metricValue) { _, newValue in syncText(with: newValue) }
        .onChange(of: unitSystem) { _, _ in text = formatted(metricValue) }
        .onChange(of: temperatureUnit) { _, _ in text = formatted(metricValue) }
    }

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = try? Double(trimmed, format: .number), value.isFinite else { return nil }
        return value
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "" }
        return toDisplay(value).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private func syncText(with value: Double?) {
        let shown = Self.parse(text).map(toMetric)
        switch (shown, value) {
        case (nil, nil): return
        case let (a?, b?) where abs(a - b) < 0.005: return
        default: text = formatted(value)
        }
    }

    @ViewBuilder
    private var unitToggle: some View {
        if quantity == .temperature {
            UnitToggle(
                options: TemperatureUnit.allCases,
                selection: Binding(get: { temperatureUnit }, set: { temperatureUnit = $0; unitsChanged() }),
                label: \.title
            )
        } else {
            UnitToggle(
                options: UnitSystem.allCases,
                selection: Binding(get: { unitSystem }, set: { unitSystem = $0; unitsChanged() }),
                label: { Self.unitLabel(quantity, $0) }
            )
        }
    }

    private func unitsChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
        // Widgets and Live Activities format amounts with the same setting.
        TrackerStore.shared.scheduleSideEffects()
    }

    static func unitLabel(_ quantity: Quantity, _ system: UnitSystem) -> String {
        switch quantity {
        case .volume: return system == .metric ? String(localized: "ml") : String(localized: "oz")
        case .weight: return system == .metric ? String(localized: "kg") : String(localized: "lb")
        case .length: return system == .metric ? String(localized: "cm") : String(localized: "in")
        case .temperature: return system == .metric ? TemperatureUnit.celsius.title : TemperatureUnit.fahrenheit.title
        }
    }
}

/// Compact two-way unit switch ("ml | oz") shown next to a number field.
struct UnitToggle<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(selected ? Color.accentColor : .clear, in: Capsule())
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Quick volume presets for bottles, in the user's unit.
struct VolumePresets: View {
    @Binding var metricValue: Double?
    @AppStorage(SettingsKey.unitSystem, store: SharedContainer.defaults) private var unitSystem: UnitSystem = AppSettings.unitSystem

    private var presets: [Double] {
        unitSystem == .metric
            ? [60, 90, 120, 150, 180, 210]
            : [2, 3, 4, 5, 6, 7].map(UnitConversion.ml(fromOunces:))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { ml in
                    let selected = abs((metricValue ?? -1) - ml) < 0.5
                    Button {
                        metricValue = ml
                    } label: {
                        ChipLabel(title: Fmt.volume(ml, unit: unitSystem), selected: selected, tint: .orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Visual for one selectable pill.
struct ChipLabel: View {
    var title: String
    var systemImage: String?
    var selected: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(title).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(selected ? tint : Color(.tertiarySystemFill), in: Capsule())
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Capsule())
    }
}

/// A row of pills that wraps onto more lines as needed, used instead of
/// drop-down menus so every choice is visible and one tap away.
struct ChipPicker<Value: Hashable>: View {
    var title: String?
    var options: [Value]
    @Binding var selection: Value?
    /// Tapping the selected pill again clears an optional field.
    var allowsDeselect = true
    var tint: Color = .accentColor
    var label: (Value) -> String
    var systemImage: ((Value) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = selection == option
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selection = selected && allowsDeselect ? nil : option
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        ChipLabel(title: label(option), systemImage: systemImage?(option), selected: selected, tint: tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

extension ChipPicker {
    /// For fields that always have a value.
    init(
        title: String?,
        options: [Value],
        value selection: Binding<Value>,
        tint: Color = .accentColor,
        label: @escaping (Value) -> String,
        systemImage: ((Value) -> String)? = nil
    ) {
        self.init(
            title: title,
            options: options,
            selection: Binding<Value?>(get: { selection.wrappedValue }, set: { if let v = $0 { selection.wrappedValue = v } }),
            allowsDeselect: false,
            tint: tint,
            label: label,
            systemImage: systemImage
        )
    }
}

/// Like `ChipPicker`, but any number of pills can be on. The selection keeps
/// the order of `options`.
struct MultiChipPicker<Value: Hashable>: View {
    var title: String?
    var options: [Value]
    @Binding var selection: [Value]
    var tint: Color = .accentColor
    var label: (Value) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = selection.contains(option)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            let chosen = Set(selection).symmetricDifference([option])
                            selection = options.filter(chosen.contains)
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        ChipLabel(title: label(option), systemImage: selected ? "checkmark" : nil, selected: selected, tint: tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Two or three big pill segments with a sliding highlight, used in place of
/// the system segmented control at the top of sheets.
struct PillSegmentedControl<Value: Hashable>: View {
    struct Segment {
        var value: Value
        var title: String
        var systemImage: String
    }

    var segments: [Segment]
    @Binding var selection: Value
    var tint: Color = .accentColor
    @Namespace private var highlight
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.value) { segment in
                let selected = segment.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = segment.value }
                } label: {
                    // At accessibility text sizes two segments can't fit an icon and
                    // a word each, so drop the icon and let the title wrap rather
                    // than truncate ("Ti…").
                    Group {
                        if typeSize.isAccessibilitySize {
                            Text(segment.title)
                        } else {
                            Label(segment.title, systemImage: segment.systemImage)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .background {
                        if selected {
                            Capsule().fill(tint.gradient).matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Lays children out left to right, wrapping to a new line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * (lineSpacing ?? spacing)
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? min(size.width, maxWidth) : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Picks a photo and stores it as compressed JPEG data.
struct PhotoField: View {
    var title: String
    @Binding var data: Data?
    @State private var item: PhotosPickerItem?

    var body: some View {
        HStack {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label(data == nil ? title : String(localized: "Change Photo"), systemImage: "photo")
            }
            if data != nil {
                Spacer()
                Button(role: .destructive) {
                    data = nil
                    item = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove Photo"))
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                // A photo that can't be read keeps the current one, and an older
                // pick that finishes late doesn't replace a newer one.
                guard let raw = try? await newItem.loadTransferable(type: Data.self),
                      let jpeg = ImageCompressor.jpeg(from: raw),
                      item == newItem else { return }
                data = jpeg
            }
        }
    }
}

enum ImageCompressor {
    /// Downscales to at most `maxDimension` px and re-encodes as JPEG to keep iCloud usage small.
    static func jpeg(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.75) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// System share sheet (AirDrop, Save to Files, iCloud Drive, Mail…).
struct ActivityShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareableFile: Identifiable {
    let url: URL
    var id: URL { url }
}

extension UIApplication {
    /// The view controller currently on top, for presenting UIKit-only screens.
    var topViewController: UIViewController? {
        let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Undo toast

/// A short "done" message with Undo, shown after one-tap actions and deletions.
struct UndoToast: Identifiable {
    let id = UUID()
    var message: String
    var undo: () -> Void
    /// Optional second button, e.g. "Add Amount" after a pumping timer stops.
    var action: (title: String, perform: () -> Void)?
}

struct UndoToastView: View {
    var toast: UndoToast
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            if let action = toast.action {
                Button(action.title) {
                    action.perform()
                    dismiss()
                }
                .font(.subheadline.bold())
            }
            Button("Undo") {
                toast.undo()
                dismiss()
            }
            .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

private struct UndoToastModifier: ViewModifier {
    @Binding var toast: UndoToast?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let toast {
                    UndoToastView(toast: toast) { self.toast = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: toast?.id)
            // Each toast stays for a few seconds; a newer one restarts the clock.
            .task(id: toast?.id) {
                guard let shown = toast?.id else { return }
                // A newer toast cancels this wait; it must not clear the newer one.
                guard (try? await Task.sleep(for: .seconds(6))) != nil, toast?.id == shown else { return }
                toast = nil
            }
    }
}

extension View {
    /// Shows the toast above the tab bar until it times out or is tapped.
    func undoToast(_ toast: Binding<UndoToast?>) -> some View {
        modifier(UndoToastModifier(toast: toast))
    }
}

// MARK: - Swipe to delete

/// Swipe left to reveal Delete, for rows that are not in a List (which has
/// swipeActions built in). Tap the row to open it, or to close the swipe.
struct SwipeToDeleteRow<Content: View>: View {
    var onTap: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var revealed = false
    private let buttonWidth: CGFloat = 72

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                if revealed { close() } else { onTap() }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(role: .destructive) {
                    close()
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete"))
                .opacity(offset < -8 ? 1 : 0)
            }
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let base: CGFloat = revealed ? -buttonWidth : 0
                        offset = min(0, max(-buttonWidth - 16, base + value.translation.width))
                    }
                    .onEnded { _ in
                        withAnimation(.snappy(duration: 0.2)) {
                            revealed = offset < -buttonWidth / 2
                            offset = revealed ? -buttonWidth : 0
                        }
                    }
            )
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) {
            revealed = false
            offset = 0
        }
    }
}

/// A `TimelineView` that follows `AppClock`: it ticks normally, and renders a
/// single frame at the pinned time when the clock is fixed.
struct ClockTimeline<Content: View>: View {
    var interval: TimeInterval
    @ViewBuilder var content: (Date) -> Content

    init(every interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.content = content
    }

    var body: some View {
        if let fixed = AppClock.fixed {
            content(fixed)
        } else {
            TimelineView(.periodic(from: .now, by: interval)) { context in
                content(context.date)
            }
        }
    }
}

// MARK: - Tips

/// One-time hints (TipKit) for features that have no visible button of their
/// own. Each shows once and goes away for good when dismissed. They are off in
/// demo mode and tests (see `TinytideTips.configure`).
enum TinytideTips {
    /// Donated when a timer starts or an entry is added.
    static let entryLogged = Tips.Event(id: "entryLogged")

    static let holdForMore = HoldForMoreTip()
    static let lockScreen = LockScreenTip()
    static let invite = InviteFamilyTip()

    static func configure() {
        guard !DemoMode.isEnabled, !PersistenceController.isRunningTests else { return }
        // At most one new tip a day, so a first session isn't a pile of popovers.
        try? Tips.configure([.displayFrequency(.daily)])
    }

    static func logged() {
        Task { await entryLogged.donate() }
    }
}

/// Shown on the timer buttons once the user has logged a few things with a tap.
struct HoldForMoreTip: Tip {
    var title: Text { Text("Touch and Hold for More") }
    var message: Text? { Text("Hold a timer to pick a side, add details before starting, or log one from earlier.") }
    var image: Image? { Image(systemName: "hand.tap.fill") }

    var rules: [Rule] {
        #Rule(TinytideTips.entryLogged) { $0.donations.count >= 3 }
    }
}

/// Shown under the first running timer.
struct LockScreenTip: Tip {
    var title: Text { Text("Your Timer Keeps Going") }
    var message: Text? { Text("Stop it or switch sides from the Lock Screen or Dynamic Island. Add a Tinytide widget to your Home Screen for one-tap logging.") }
    var image: Image? { Image(systemName: "lock.iphone") }
}

/// Shown on Today after a few entries, until the baby is shared.
struct InviteFamilyTip: Tip {
    var title: Text { Text("Track Together") }
    var message: Text? { Text("Invite a partner, grandparent or nanny in Settings → Family & Caregivers. Everyone sees the same entries in real time.") }
    var image: Image? { Image(systemName: "person.2.fill") }

    var rules: [Rule] {
        #Rule(TinytideTips.entryLogged) { $0.donations.count >= 8 }
    }
}
