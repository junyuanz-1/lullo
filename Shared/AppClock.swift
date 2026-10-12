import Foundation

/// The app's idea of "now". Normally the real time; snapshot tests and App Store
/// screenshots pin it so every run renders exactly the same screens.
enum AppClock {
    static var fixed: Date?

    static var now: Date { fixed ?? Date() }
}
