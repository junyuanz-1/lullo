import StoreKit
import SwiftUI

/// Subscription page for "Tinytide Supporter", built on Apple's SubscriptionStoreView
/// (which shows prices, renewal terms, restore and policy links as App Review expects).
struct SupporterView: View {
    @StateObject private var supporter = Supporter.shared
    @State private var managingSubscription = false

    var body: some View {
        SubscriptionStoreView(productIDs: Supporter.productIDs) {
            VStack(spacing: 16) {
                Image(systemName: supporter.isSupporter ? "heart.circle.fill" : "moon.stars.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.pink.gradient)
                Text(supporter.isSupporter
                     ? String(localized: "You're a Tinytide Supporter")
                     : String(localized: "Become a Tinytide Supporter"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Every tracking feature stays free for everyone. Supporters keep Tinytide independent and get a few extras as a thank-you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    perk("app.badge.fill", String(localized: "4 alternate app icons"))
                    perk("paintpalette.fill", String(localized: "5 theme colors"))
                    perk("heart.fill", String(localized: "Supporter badge"))
                    perk("person.2.fill", String(localized: "Shared with your family through Family Sharing"))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePolicyDestination(url: AppLinks.privacyPolicy, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: AppLinks.termsOfUse, for: .termsOfService)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result, case .verified(let transaction) = verification {
                await transaction.finish()
            }
            await supporter.refresh()
        }
        .toolbar {
            if supporter.isSupporter {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Manage") { managingSubscription = true }
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $managingSubscription)
        .navigationTitle("Tinytide Supporter")
        .navigationBarTitleDisplayMode(.inline)
        .task { await supporter.refresh() }
    }

    private func perk(_ systemImage: String, _ title: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.pink)
        }
    }
}

/// App icon and theme pickers. Non-default options need an active subscription.
struct AppearanceView: View {
    @StateObject private var supporter = Supporter.shared
    @AppStorage(Appearance.themeKey, store: SharedContainer.defaults) private var theme: AppTheme = .lullaby
    @State private var currentIcon = AlternateIcon.current
    @State private var showingSupporter = false

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 16)]

    var body: some View {
        Form {
            if !supporter.isSupporter {
                Section {
                    Button {
                        showingSupporter = true
                    } label: {
                        Label("Unlock with Tinytide Supporter", systemImage: "lock.open.fill")
                    }
                }
            }
            Section("App Icon") {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AlternateIcon.allCases) { icon in
                        Button {
                            choose(icon)
                        } label: {
                            VStack(spacing: 6) {
                                Image(icon.previewImage)
                                    .resizable()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(currentIcon == icon ? Color.accentColor : .clear, lineWidth: 3)
                                    )
                                    .overlay(alignment: .topTrailing) { lockBadge(locked: !icon.isFree) }
                                Text(icon.title).font(.caption).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Theme Color") {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        if option.isFree || supporter.isSupporter {
                            theme = option
                        } else {
                            showingSupporter = true
                        }
                    } label: {
                        HStack {
                            Circle().fill(option.color).frame(width: 24, height: 24)
                            Text(option.title).foregroundStyle(.primary)
                            Spacer()
                            if theme == option {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            } else if !option.isFree && !supporter.isSupporter {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSupporter) {
            NavigationStack { SupporterView() }
        }
        .onAppear { currentIcon = AlternateIcon.current }
    }

    @ViewBuilder
    private func lockBadge(locked: Bool) -> some View {
        if locked && !supporter.isSupporter {
            Image(systemName: "lock.fill")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.55), in: Circle())
                .offset(x: 6, y: -6)
        }
    }

    private func choose(_ icon: AlternateIcon) {
        guard icon.isFree || supporter.isSupporter else {
            showingSupporter = true
            return
        }
        Task {
            do {
                try await Appearance.setIcon(icon)
                currentIcon = icon
            } catch {
                currentIcon = AlternateIcon.current
            }
        }
    }
}
