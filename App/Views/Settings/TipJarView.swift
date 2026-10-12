import StoreKit
import SwiftUI
import UIKit

/// "Support Tinytide": three optional tips and a thank-you page.
struct TipJarView: View {
    @StateObject private var tipJar = TipJar.shared
    @State private var thankedTier: TipJar.Tier?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                switch tipJar.loadState {
                case .idle, .loading:
                    ProgressView().padding(.vertical, 40)
                case .failed(let error):
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await tipJar.loadProducts() } }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 24)
                case .loaded:
                    VStack(spacing: 12) {
                        ForEach(TipJar.Tier.allCases) { tier in
                            TipRow(
                                tier: tier,
                                product: tipJar.products[tier],
                                isPurchasing: tipJar.purchasing == tier,
                                isDisabled: tipJar.purchasing != nil
                            ) {
                                Task { await buy(tier) }
                            }
                        }
                    }
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Tips are optional one-time purchases. They don't unlock anything: every feature stays free for everyone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Support Tinytide")
        .navigationBarTitleDisplayMode(.inline)
        .task { if tipJar.loadState == .idle { await tipJar.loadProducts() } }
        .sheet(item: $thankedTier) { tier in
            TipThanksView(tier: tier, totalTips: tipJar.tipCount)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink.gradient)
            Text("Enjoying Tinytide?")
                .font(.title2.bold())
            Text("Tinytide is an independent app with no ads and no tracking. If it has made your nights a little easier, a tip helps keep it going.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func buy(_ tier: TipJar.Tier) async {
        message = nil
        switch await tipJar.purchase(tier) {
        case .thanked(let tier):
            thankedTier = tier
        case .pending:
            message = String(localized: "Your tip is waiting for approval. Thank you!")
        case .cancelled:
            break
        case .failed(let error):
            message = error
        }
    }
}

private struct TipRow: View {
    let tier: TipJar.Tier
    let product: Product?
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(tier.emoji)
                    .font(.system(size: 34))
                    .frame(width: 52, height: 52)
                    .background(Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product?.displayName ?? tier.fallbackTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(tier.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Group {
                    if isPurchasing {
                        ProgressView()
                    } else {
                        Text(product?.displayPrice ?? "—")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.pink, in: Capsule())
                    }
                }
                .frame(minWidth: 72)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || product == nil)
        .accessibilityElement(children: .combine)
    }
}

struct TipThanksView: View {
    @Environment(\.dismiss) private var dismiss
    let tier: TipJar.Tier
    let totalTips: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .scaleEffect(appeared ? 1 : 0.6)
                Text(tier.emoji)
                    .font(.system(size: 72))
                    .scaleEffect(appeared ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared ? 0 : -20))
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.55), value: appeared)

            Text("Thank you!")
                .font(.largeTitle.bold())
            Text("Your support means a lot. It goes straight into making Tinytide better for every tired parent out there.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            if totalTips > 1 {
                Label(String(localized: "You've supported Tinytide \(String(totalTips)) times 💖"), systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.pink)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .padding(.horizontal)
        }
        .padding(.bottom)
        .presentationDetents([.large])
        .onAppear {
            appeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
