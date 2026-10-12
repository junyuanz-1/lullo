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
struct MeasurementField: View {
    enum Quantity {
        case volume, weight, length, temperature
    }

    var title: String
    @Binding var metricValue: Double?
    var quantity: Quantity

    private var unitSystem: UnitSystem { AppSettings.unitSystem }
    private var temperatureUnit: TemperatureUnit { AppSettings.temperatureUnit }

    private var unitLabel: String {
        switch quantity {
        case .volume: return unitSystem == .metric ? String(localized: "ml") : String(localized: "oz")
        case .weight: return unitSystem == .metric ? String(localized: "kg") : String(localized: "lb")
        case .length: return unitSystem == .metric ? String(localized: "cm") : String(localized: "in")
        case .temperature: return temperatureUnit.title
        }
    }

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
        HStack {
            Text(title)
            Spacer()
            TextField(unitLabel, value: displayBinding, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text(unitLabel).foregroundStyle(.secondary)
        }
    }
}

/// Quick volume presets for bottles, in the user's unit.
struct VolumePresets: View {
    @Binding var metricValue: Double?

    private var presets: [Double] {
        AppSettings.unitSystem == .metric
            ? [60, 90, 120, 150, 180, 210]
            : [2, 3, 4, 5, 6, 7].map(UnitConversion.ml(fromOunces:))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(presets, id: \.self) { ml in
                    Button(Fmt.volume(ml)) { metricValue = ml }
                        .buttonStyle(.bordered)
                        .tint(abs((metricValue ?? -1) - ml) < 0.5 ? .orange : .secondary)
                }
            }
        }
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
                Label(data == nil ? title : String(localized: "Change photo"), systemImage: "photo")
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
                .accessibilityLabel(Text("Remove photo"))
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
