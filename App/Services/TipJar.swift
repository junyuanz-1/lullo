import Foundation
import OSLog
import StoreKit

/// Optional tips through In-App Purchase. Tips are consumables and unlock
/// nothing, which keeps them within App Store guideline 3.1.1.
@MainActor
final class TipJar: ObservableObject {
    static let shared = TipJar()

    enum Tier: String, CaseIterable, Identifiable {
        case small = "tinytide.tip.small"
        case medium = "tinytide.tip.medium"
        case large = "tinytide.tip.large"

        var id: String { rawValue }
        var productID: String { rawValue }

        var emoji: String {
            switch self {
            case .small: return "☕️"
            case .medium: return "🍰"
            case .large: return "🍱"
            }
        }

        var fallbackTitle: String {
            switch self {
            case .small: return String(localized: "A cup of coffee")
            case .medium: return String(localized: "A slice of cake")
            case .large: return String(localized: "A nice lunch")
            }
        }

        var blurb: String {
            switch self {
            case .small: return String(localized: "For the 3 a.m. feeds.")
            case .medium: return String(localized: "Helps keep Tinytide ad-free.")
            case .large: return String(localized: "Funds new features for every family.")
            }
        }
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseResult: Equatable {
        case thanked(Tier)
        case pending
        case cancelled
        case failed(String)
    }

    @Published private(set) var products: [Tier: Product] = [:]
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var purchasing: Tier?

    private let logger = Logger(subsystem: "Tinytide", category: "TipJar")
    private let tipCountKey = "tipJarTipCount"
    private var updatesTask: Task<Void, Never>?

    /// Number of tips this device has sent, for a small thank-you note.
    var tipCount: Int { SharedContainer.defaults.integer(forKey: tipCountKey) }

    /// Finishes transactions that complete outside the app (Ask to Buy, interrupted
    /// purchases, subscription renewals) for both tips and the Supporter subscription.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: Tier.allCases.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                Tier(rawValue: product.id).map { ($0, product) }
            })
            loadState = products.isEmpty ? .failed(String(localized: "Tips are not available right now.")) : .loaded
        } catch {
            logger.error("Loading tip products failed: \(error.localizedDescription)")
            loadState = .failed(error.localizedDescription)
        }
    }

    func purchase(_ tier: Tier) async -> PurchaseResult {
        guard let product = products[tier] else { return .failed(String(localized: "Tips are not available right now.")) }
        purchasing = tier
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed(String(localized: "The purchase could not be verified."))
                }
                await transaction.finish()
                recordTip()
                return .thanked(tier)
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            logger.error("Tip purchase failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        if Tier(rawValue: transaction.productID) != nil, transaction.revocationDate == nil {
            recordTip()
        }
        await transaction.finish()
        if Supporter.productIDs.contains(transaction.productID) {
            await Supporter.shared.refresh()
        }
    }

    private func recordTip() {
        SharedContainer.defaults.set(tipCount + 1, forKey: tipCountKey)
    }
}
