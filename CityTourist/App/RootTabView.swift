import SwiftUI

struct RootTabView: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: TabID = .explore
    @State private var hasChosenInitialTab = false
    @State private var isShowingIntro = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboardingStarted = false

    private enum TabID: Hashable { case explore, saved, trips, profile }

    var body: some View {
        Group {
            if store.storageIssue == .unreadable {
                ContentUnavailableView {
                    Label("Your trips couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved file has been preserved. Try again to reopen it.")
                } actions: {
                    Button("Try again") { store.retryStorage() }
                        .buttonStyle(.borderedProminent)
                }
            } else if needsOnboarding {
                OnboardingView {
                    withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.35)) { hasCompletedOnboarding = true }
                }
                .onAppear { onboardingStarted = true }
                .transition(.opacity)
            } else {
                tabs
                    .transition(.opacity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if store.storageIssue == .unsaved {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Changes haven’t been saved", systemImage: "exclamationmark.triangle")
                                    .font(.subheadline.weight(.semibold))
                                Text("Keep the app open and try saving again.")
                                    .font(.subheadline)
                                Button("Save again") { store.retryStorage() }
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Palette.surface)
                        }
                    }
            }
        }
        .tint(Brand.rausch)
        .overlay {
            if isShowingIntro && !reduceMotion && !voiceOver && store.storageIssue == nil {
                LaunchIntroView()
                    .onTapGesture { isShowingIntro = false }
                    .transition(.opacity)
            }
        }
        .onAppear {
            guard !hasChosenInitialTab else { return }
            hasChosenInitialTab = true
            if store.tripToday != nil { selection = .trips }
        }
        .task {
            guard isShowingIntro else { return }
            guard !reduceMotion && !voiceOver else {
                isShowingIntro = false
                return
            }
            do { try await Task.sleep(for: .milliseconds(750)) }
            catch { isShowingIntro = false; return }
            withAnimation(.easeOut(duration: 0.18)) { isShowingIntro = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { isShowingIntro = false }
            if phase == .active { Task { await authentication.restoreSession() } }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { isShowingIntro = false }
        }
        .onChange(of: voiceOver) { _, enabled in
            if enabled { isShowingIntro = false }
        }
    }

    /// New travellers get the walk-through once. Anyone who already has trips,
    /// saved places or an account from an earlier build goes straight in. Once
    /// it has started, signing in or saving along the way doesn't cut it short.
    private var needsOnboarding: Bool {
        guard !hasCompletedOnboarding else { return false }
        return onboardingStarted
            || (store.trips.isEmpty && store.savedPlaceIDs.isEmpty && authentication.session == nil)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Explore", systemImage: "magnifyingglass", value: TabID.explore) {
                ExploreView()
            }
            Tab("Saved", systemImage: "heart", value: TabID.saved) {
                SavedView()
            }
            Tab("Trips", systemImage: "airplane", value: TabID.trips) {
                TripsView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: TabID.profile) {
                ProfileView()
            }
        }
        .tint(Brand.rausch)
    }
}

#Preview {
    RootTabView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog()).environment(AuthenticationStore()).environment(AvatarStore())
        .environment(WeatherStore())
        .environment(RouteStore())
        .environment(PlaceShorts(makeService: { nil }, cacheURL: nil))
}
