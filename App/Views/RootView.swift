import BabyCore
import CoreData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: TrackerStore
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)])
    private var babies: FetchedResults<Baby>
    @AppStorage(Appearance.themeKey, store: SharedContainer.defaults) private var theme: AppTheme = .lullaby

    private var selectedBaby: Baby? {
        babies.first { $0.id == store.selectedBabyID } ?? babies.first
    }

    var body: some View {
        content.tint(theme.color)
    }

    @ViewBuilder
    private var content: some View {
        if let baby = selectedBaby {
            TabView {
                HomeView(baby: baby)
                    .tabItem { Label("Today", systemImage: "house.fill") }
                HistoryView(baby: baby)
                    .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                TrendsView(baby: baby)
                    .tabItem { Label("Trends", systemImage: "chart.bar.xaxis") }
                GrowthView(baby: baby)
                    .tabItem { Label("Growth", systemImage: "chart.line.uptrend.xyaxis") }
                SettingsView()
                    .tabItem { Label("More", systemImage: "gearshape.fill") }
            }
            .id(baby.objectID)
        } else {
            OnboardingView()
        }
    }
}

/// Toolbar menu for switching between babies.
struct BabySwitcher: View {
    @EnvironmentObject private var store: TrackerStore
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)])
    private var babies: FetchedResults<Baby>
    @ObservedObject var baby: Baby
    @State private var showingAddBaby = false

    var body: some View {
        Menu {
            ForEach(babies) { candidate in
                Button {
                    store.selectedBabyID = candidate.id
                } label: {
                    if candidate.objectID == baby.objectID {
                        Label(candidate.displayName, systemImage: "checkmark")
                    } else {
                        Text(candidate.displayName)
                    }
                }
            }
            Divider()
            Button {
                showingAddBaby = true
            } label: {
                Label("Add Baby", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                BabyAvatar(photoData: baby.photoData, name: baby.displayName, size: 30)
                Text(baby.displayName).font(.headline).foregroundStyle(.primary)
                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text("Switch Baby"))
        .sheet(isPresented: $showingAddBaby) {
            NavigationStack { BabyFormView(baby: nil) }
        }
    }
}

struct OnboardingView: View {
    @State private var showingForm = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 72))
                .foregroundStyle(.indigo.gradient)
            Text("Welcome to Tinytide")
                .font(.largeTitle.bold())
            Text("Track sleep, feeds, diapers and growth. Everything syncs privately through your iCloud and can be shared with family.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Button {
                showingForm = true
            } label: {
                Text("Add Your Baby")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Text("Invited by a family member? Open their invitation link and the shared baby will appear here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .sheet(isPresented: $showingForm) {
            NavigationStack { BabyFormView(baby: nil) }
        }
    }
}
