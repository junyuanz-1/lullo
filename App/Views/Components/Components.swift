import BabyCore
import PhotosUI
import SwiftUI
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

    var body: some View {
        let placeholder = "0"
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, value: displayBinding, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            unitToggle
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

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.value) { segment in
                let selected = segment.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = segment.value }
                } label: {
                    Label(segment.title, systemImage: segment.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                if let raw = try? await newItem.loadTransferable(type: Data.self) {
                    data = ImageCompressor.jpeg(from: raw)
                }
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
