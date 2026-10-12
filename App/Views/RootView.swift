import BabyCore
import CoreData
import SwiftUI

enum RootTab: Hashable {
    case today, log, trends, growth, more
}

struct RootView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var tab = DemoMode.initialTab
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
            // Each tab is rebuilt for the new baby (their fetch requests are set up
            // in init), while the TabView itself keeps the selected tab.
            TabView(selection: $tab) {
                HomeView(baby: baby)
                    .id(baby.objectID)
                    .tabItem { Label("Today", systemImage: "house.fill") }
                    .tag(RootTab.today)
                HistoryView(baby: baby)
                    .id(baby.objectID)
                    .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                    .tag(RootTab.log)
                TrendsView(baby: baby)
                    .id(baby.objectID)
                    .tabItem { Label("Trends", systemImage: "chart.bar.xaxis") }
                    .tag(RootTab.trends)
                GrowthView(baby: baby)
                    .id(baby.objectID)
                    .tabItem { Label("Growth", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(RootTab.growth)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(RootTab.more)
            }
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
        if babies.count > 1 {
            menu
        } else {
            // One baby: nothing to switch to, so no drop-down affordance. Adding a
            // baby lives in More.
            label(showsChevron: false)
        }
    }

    private var menu: some View {
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
            label(showsChevron: true)
        }
        .accessibilityLabel(Text("Switch Baby"))
        .sheet(isPresented: $showingAddBaby) {
            NavigationStack { BabyFormView(baby: nil) }
        }
    }

    private func label(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            BabyAvatar(photoData: baby.photoData, name: baby.displayName, size: 30)
            Text(baby.displayName).font(.headline).foregroundStyle(.primary)
            if showsChevron {
                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
            }
        }
    }
}

struct OnboardingView: View {
    @State private var showingForm = false
    @AppStorage(SettingsKey.unitSystem, store: SharedContainer.defaults) private var unitSystem: UnitSystem = AppSettings.unitSystem

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.indigo.gradient)
                    .padding(.top, 40)
                Text("Welcome to Tinytide")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                // What the app does, so the main features are known from day one
                // instead of found by accident.
                VStack(alignment: .leading, spacing: 18) {
                    feature(
                        "timer", .indigo,
                        String(localized: "One-Tap Timers"),
                        String(localized: "Start sleep, nursing or pumping with a tap. Timers keep running on the Lock Screen and Dynamic Island.")
                    )
                    feature(
                        "chart.bar.xaxis", .orange,
                        String(localized: "Patterns and Nap Times"),
                        String(localized: "See daily trends and when the next nap is due, based on age and your baby's own rhythm.")
                    )
                    feature(
                        "person.2.fill", .blue,
                        String(localized: "Share with Family"),
                        String(localized: "Everything syncs privately through your iCloud. Invite a partner or nanny to log together.")
                    )
                }
                .padding(.horizontal)

                ChipPicker(title: String(localized: "Units"), options: UnitSystem.allCases, value: $unitSystem, label: \.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    showingForm = true
                } label: {
                    Text("Add Your Baby")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                Text("Invited by a family member? Open their invitation link and the shared baby will appear here.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingForm) {
            NavigationStack { BabyFormView(baby: nil) }
        }
    }

    private func feature(_ systemImage: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
