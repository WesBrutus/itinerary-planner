import SwiftUI
import UserNotifications

/// The first-launch walk-through. Each step is a stop on the route: say what
/// you like, make an account, turn on leave-time reminders, and you're off.
struct OnboardingView: View {
    let onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, interests, account, reminders, done
    }

    @Environment(AppStore.self) private var store
    @Environment(AuthenticationStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var movingForward = true
    @State private var picked: Set<PlaceCategory> = []
    @State private var bellRings = 0

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome { header.transition(.opacity) }
            content
                .id(step)
                .transition(stepTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: picked)
        .sensoryFeedback(trigger: step) { _, new in
            new == .done ? SensoryFeedback.success : SensoryFeedback.impact(weight: .light)
        }
        .onChange(of: auth.session?.user.id) { _, id in
            // Signing in is its own small win: move on without another tap.
            if id != nil, step == .account { go(to: .reminders) }
        }
    }

    // MARK: Moving between steps

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(to next: Step) {
        movingForward = next.rawValue > step.rawValue
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)) {
            step = next
        }
    }

    /// The account step is left out when sign-in isn't set up or already done.
    private var offersAccount: Bool { auth.isConfigured && auth.session == nil }

    private func back() {
        switch step {
        case .welcome, .interests: go(to: .welcome)
        case .account: go(to: .interests)
        case .reminders, .done: go(to: offersAccount ? .account : .interests)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L10n.text("Back"))
            .opacity(step == .done ? 0 : 1)
            .disabled(step == .done)
            RouteProgress(stops: Step.allCases.count - 1, reached: step.rawValue)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .interests: interests
        case .account: account
        case .reminders: reminders
        case .done: done
        }
    }

    // MARK: Steps

    private var welcome: some View {
        page {
            RouteHero().frame(height: 220).padding(.top, 24)
            heading("Your city days, stop by stop.",
                    "Pick what you love and City Tourist lines up places, opening hours and travel times into a day that works.")
        } actions: {
            PrimaryButton(title: "Get started") { go(to: .interests) }
            if offersAccount {
                quietButton("I already have an account") { go(to: .account) }
            }
        }
    }

    private var interests: some View {
        page {
            heading("What do you love on a trip?",
                    picked.isEmpty ? "Pick a few. Your first day plans start from these."
                                   : "Great picks. You can adjust them for each plan.")
            VStack(spacing: 12) {
                ForEach(FirstDayPlanner.interests) { category in
                    InterestRow(category: category, isSelected: picked.contains(category)) {
                        if picked.contains(category) { picked.remove(category) } else { picked.insert(category) }
                    }
                }
            }
        } actions: {
            PrimaryButton(title: "Continue", isEnabled: !picked.isEmpty) {
                var profile = store.profile
                profile.interests = FirstDayPlanner.interests.filter { picked.contains($0) }
                store.updateProfile(profile)
                go(to: offersAccount ? .account : .reminders)
            }
            quietButton("Not now") { go(to: offersAccount ? .account : .reminders) }
        }
        .onAppear { if picked.isEmpty { picked = Set(store.profile.interests ?? []) } }
    }

    private var account: some View {
        page {
            heading("Create your account",
                    "Log in or sign up with Apple or your phone number. Trips and saved places stay on this device.")
            AccountAccessView()
        } actions: {
            quietButton("Not now") { auth.changeNumber(); go(to: .reminders) }
            Link(destination: ProfileView.privacyURL) {
                Text(L10n.text("By continuing you agree to our Privacy Policy."))
                    .font(.footnote).underline()
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var reminders: some View {
        page {
            Image(systemName: "bell.badge")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Brand.rausch)
                .symbolEffect(.bounce, value: bellRings)
                .frame(width: 112, height: 112)
                .background(Brand.rausch.opacity(0.1), in: Circle())
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .accessibilityHidden(true)
            heading("Never miss a stop",
                    "Get a reminder when it’s time to leave for your next stop.")
        } actions: {
            PrimaryButton(title: "Turn on reminders") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    go(to: .done)
                }
            }
            quietButton("Not now") { go(to: .done) }
        }
        .task {
            // The bell rings once after the step settles.
            try? await Task.sleep(for: .milliseconds(450))
            if !reduceMotion { bellRings += 1 }
        }
    }

    private var done: some View {
        let name = store.profile.displayName.split(separator: " ").first.map(String.init) ?? ""
        return page {
            RouteHero(completed: true).frame(height: 220).padding(.top, 24)
            heading(name.isEmpty ? L10n.text("You’re all set") : L10n.format("You’re all set, %@", name),
                    "Search a city and plan your first day.")
        } actions: {
            PrimaryButton(title: "Start exploring", action: onFinish)
        }
    }

    // MARK: Building blocks

    /// Scrolling content with the step's actions pinned underneath.
    private func page<Content: View, Actions: View>(@ViewBuilder _ content: () -> Content,
                                                    @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) { content() }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 8) { actions() }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title)).displayStyle()
            Text(L10n.text(subtitle)).font(.body).foregroundStyle(Palette.inkMuted)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: subtitle)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.text(title))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .underline()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// One selectable interest. The icon bounces and a check springs in when it's
/// picked, so every tap gets an answer.
private struct InterestRow: View {
    let category: PlaceCategory
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: category.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Palette.ink)
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Brand.rausch : Palette.surface, in: Circle())
                Text(category.title).cardTitleStyle()
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Brand.rausch)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.ink : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    OnboardingView { }
        .environment(AppStore(loadFromDisk: false))
        .environment(AuthenticationStore())
}
