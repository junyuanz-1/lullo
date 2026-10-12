import Foundation
import OSLog
import StoreKit
import SwiftUI
import UIKit

/// "Tinytide Supporter" auto-renewable subscription. Every tracking feature stays
/// free; supporters get cosmetic perks (alternate app icons, theme colours, a badge).
@MainActor
final class Supporter: ObservableObject {
    static let shared = Supporter()

    static let monthlyID = "tinytide.supporter.monthly"
    static let yearlyID = "tinytide.supporter.yearly"
    static let productIDs = [monthlyID, yearlyID]

    @Published private(set) var isSupporter: Bool

    private let cacheKey = "supporterActive"
    private let logger = Logger(subsystem: "Tinytide", category: "Supporter")

    init() {
        // Cached so perks don't flicker off while entitlements load at launch.
        isSupporter = SharedContainer.defaults.bool(forKey: cacheKey)
    }

    /// Re-checks the current subscription with StoreKit.
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            active = true
        }
        if isSupporter != active { logger.info("Supporter status changed: \(active)") }
        isSupporter = active
        SharedContainer.defaults.set(active, forKey: cacheKey)
        if !active { Appearance.resetSupporterPerks() }
    }
}

/// Supporter-only appearance options.
enum AppTheme: String, CaseIterable, Identifiable {
    case lullaby
    case rose
    case ocean
    case forest
    case sunset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lullaby: return String(localized: "Lullaby")
        case .rose: return String(localized: "Rose")
        case .ocean: return String(localized: "Ocean")
        case .forest: return String(localized: "Forest")
        case .sunset: return String(localized: "Sunset")
        }
    }

    var color: Color {
        switch self {
        // The asset colour itself: `.accentColor` follows the current tint,
        // which is whichever theme is selected.
        case .lullaby: return Color("AccentColor")
        case .rose: return .pink
        case .ocean: return .teal
        case .forest: return .green
        case .sunset: return .orange
        }
    }

    var isFree: Bool { self == .lullaby }
}

enum AlternateIcon: String, CaseIterable, Identifiable {
    case standard
    case midnight
    case sunrise
    case mint
    case blossom

    var id: String { rawValue }

    /// Name of the alternate icon set in the asset catalog; nil for the primary icon.
    var iconName: String? {
        switch self {
        case .standard: return nil
        case .midnight: return "AppIcon-Midnight"
        case .sunrise: return "AppIcon-Sunrise"
        case .mint: return "AppIcon-Mint"
        case .blossom: return "AppIcon-Blossom"
        }
    }

    var previewImage: String {
        switch self {
        case .standard: return "IconPreview-Default"
        case .midnight: return "IconPreview-Midnight"
        case .sunrise: return "IconPreview-Sunrise"
        case .mint: return "IconPreview-Mint"
        case .blossom: return "IconPreview-Blossom"
        }
    }

    var title: String {
        switch self {
        case .standard: return String(localized: "Classic")
        case .midnight: return String(localized: "Midnight")
        case .sunrise: return String(localized: "Sunrise")
        case .mint: return String(localized: "Mint")
        case .blossom: return String(localized: "Blossom")
        }
    }

    var isFree: Bool { self == .standard }

    static var current: AlternateIcon {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

enum Appearance {
    static let themeKey = "appTheme"

    @MainActor
    static func setIcon(_ icon: AlternateIcon) async throws {
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != icon.iconName else { return }
        try await UIApplication.shared.setAlternateIconName(icon.iconName)
    }

    /// Called when a subscription ends: go back to the free look.
    @MainActor
    static func resetSupporterPerks() {
        let theme = SharedContainer.defaults.string(forKey: themeKey).flatMap(AppTheme.init(rawValue:)) ?? .lullaby
        if !theme.isFree { SharedContainer.defaults.set(AppTheme.lullaby.rawValue, forKey: themeKey) }
        if !AlternateIcon.current.isFree {
            Task { try? await setIcon(.standard) }
        }
    }
}

enum AppLinks {
    /// Set PRIVACY_POLICY_URL in Config/Shared.xcconfig to wherever PRIVACY.md is published.
    static var privacyPolicy: URL {
        (Bundle.main.object(forInfoDictionaryKey: "PrivacyPolicyURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://www.apple.com/legal/privacy/")!
    }

    static let supportEmail = URL(string: "mailto:support@tinytide.app?subject=Tinytide%20Support")!
    static let supportPage = URL(string: "https://tinytide.app/support/")!

    /// Apple's standard licensed application end user license agreement.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
