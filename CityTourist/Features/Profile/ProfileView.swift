import SwiftUI
import UserNotifications
import PhotosUI

/// Profile, account access and device preferences. Trips remain local to this phone.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthenticationStore.self) private var auth
    @Environment(AvatarStore.self) private var avatar
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var editing = false
    @State private var signingIn = false
    @State private var name = ""
    @Environment(\.openURL) private var openURL
    @State private var copiedFeedbackAddress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    profileHeader
                    statistics
                    travelStyle
                    settingsSection
                    aboutSection
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Profile")
            .sheet(isPresented: $signingIn) { AccountSheet() }
            .sensoryFeedback(.success, trigger: auth.session?.user.id) { _, id in id != nil }
            .alert("Edit profile", isPresented: $editing) {
                TextField("Your name", text: $name)
                Button("Save") {
                    var profile = store.profile
                    profile.displayName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                    store.updateProfile(profile)
                }
                Button("Cancel", role: .cancel) { }
            }
            .task(id: auth.session?.user.id) { await avatar.load(auth: auth) }
            .onChange(of: selectedPhoto) { _, photo in
                Task {
                    do {
                        guard let data = try await photo?.loadTransferable(type: Data.self) else { return }
                        await avatar.update(data, auth: auth)
                    } catch { avatar.errorMessage = L10n.text("This photo could not be opened. Try another photo.") }
                    selectedPhoto = nil
                }
            }
        }
    }

    private var profileHeader: some View {
        let profileImage = avatar.image
        return VStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = profileImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Text(initials).font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Brand.rausch).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Brand.rausch.opacity(0.08))
                        }
                    }
                    .frame(width: 116, height: 116).clipShape(Circle())
                    .overlay(Circle().stroke(Brand.rausch, lineWidth: 3))
                    Image(systemName: "camera.fill").foregroundStyle(.white).padding(10).background(.black, in: Circle())
                }
            }
            .disabled(avatar.busy).accessibilityLabel(L10n.text("Change profile photo"))
            if avatar.busy { ProgressView() }
            Text(store.profile.displayName.isEmpty ? L10n.text("Your profile") : store.profile.displayName)
                .font(.title.bold())
            Label("City hopper", systemImage: "airplane")
                .foregroundStyle(Brand.rausch).padding(.horizontal, 16).padding(.vertical, 7)
                .background(Brand.rausch.opacity(0.1), in: Capsule())
            Button {
                name = store.profile.displayName; editing = true
            } label: {
                Label("Edit profile", systemImage: "pencil").font(.headline)
                    .frame(maxWidth: .infinity).padding().foregroundStyle(.white).background(.black, in: Capsule())
            }
            if let error = avatar.errorMessage { Text(error).captionStyle().foregroundStyle(Brand.rausch) }
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).stroke(Palette.hairline))
    }

    private var initials: String {
        let result = store.profile.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return result.isEmpty ? "CT" : result.uppercased()
    }
    private var statistics: some View {
        HStack(spacing: 16) {
            statistic(store.savedPlaceIDs.count, title: "Saved places", symbol: "heart", color: Brand.rausch)
            statistic(store.trips.reduce(0) { $0 + $1.days.filter { !$0.stops.isEmpty }.count },
                      title: "Days planned", symbol: "calendar", color: Brand.babu)
        }
    }
    private func statistic(_ count: Int, title: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Text(count.formatted()).font(.largeTitle.bold())
            Text(L10n.text(title)).metaStyle()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private var travelStyle: some View {
        let places = store.trips.flatMap { $0.days.flatMap(\.stops) }.compactMap { PlaceDirectory.place(id: $0.placeID) }
        let categories = Dictionary(grouping: places, by: \.category)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Your travel style").sectionTitleStyle()
            Text(places.isEmpty ? L10n.text("Plan a day to discover your travel style.") : L10n.text("What your days are made of.")).metaStyle()
            ForEach(PlaceCategory.allCases.filter { categories[$0] != nil }) { category in
                let fraction = Double(categories[category]?.count ?? 0) / Double(max(1, places.count))
                VStack(spacing: 8) {
                    HStack {
                        Label(category.title, systemImage: category.symbol)
                        Spacer()
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    }
                    ProgressView(value: fraction).tint(Brand.rausch)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").sectionTitleStyle()
            row("Notifications", symbol: "bell") { openNotificationSettings() }
            Picker("Language", selection: Binding(get: { store.profile.language }, set: { value in
                var profile = store.profile; profile.language = value; store.updateProfile(profile)
            })) { ForEach(AppLanguage.allCases) { Text($0.title).tag($0) } }
            Picker("Distance units", selection: Binding(get: { store.profile.distanceUnit }, set: { value in
                var profile = store.profile; profile.distanceUnit = value; store.updateProfile(profile)
            })) { ForEach(DistanceUnit.allCases) { Text($0.title).tag($0) } }
            Text("Account").sectionTitleStyle().padding(.top, 12)
            if let session = auth.session {
                Text(accountLabel(session.user)).metaStyle()
                Button("Sign out") { Task { await auth.signOut() } }.disabled(auth.busy)
            } else if auth.isConfigured {
                row("Log in or sign up", symbol: "person.crop.circle") { signingIn = true }
            } else {
                Text("Phone sign-in is not configured yet.").captionStyle()
            }
            Text("Trips and saved places stay on this device.").captionStyle()
            if let error = auth.errorMessage { Text(error).captionStyle().foregroundStyle(Brand.rausch) }
        }
    }

    /// The phone number for a phone account; Apple accounts show their email,
    /// which may be a private relay address, or just that Apple was used.
    private func accountLabel(_ user: AuthSession.User) -> String {
        if let phone = user.phone, !phone.isEmpty { return phone.hasPrefix("+") ? phone : "+" + phone }
        if let email = user.email, !email.isEmpty { return email }
        return L10n.text("Signed in with Apple")
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About").sectionTitleStyle().padding(.bottom, 8)
            row("Beta survey", symbol: "checklist") { openURL(BetaSurvey.url()) }
            row("Privacy", symbol: "hand.raised") { openURL(Self.privacyURL) }
            if let feedbackURL, let address = Secrets.feedbackEmail {
                row("Send feedback", symbol: "bubble.left") {
                    // Without a mail app the link goes nowhere; hand over the address instead.
                    openURL(feedbackURL) { accepted in
                        guard !accepted else { return }
                        UIPasteboard.general.string = address
                        copiedFeedbackAddress = true
                    }
                }
                if copiedFeedbackAddress {
                    Text("No mail app here, so the address is copied: \(address)").captionStyle().padding(.top, 8)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("City Tourist \(Self.version) · Beta").captionStyle()
                Text("Places and opening hours from Google. Short videos from YouTube. Events from Ticketmaster and Eventbrite. Weather from Open-Meteo. Travel times and directions from Apple Maps. AI suggestions and trip plans from Claude, by Anthropic.")
                    .captionStyle()
            }
            .padding(.top, 16)
        }
    }

    /// The first time, asks; after that, iOS only lets the Settings app
    /// change the answer.
    private func openNotificationSettings() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                store.requestNotificationPermission()
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }

    /// An email with the build already in it, when a feedback address is set.
    private var feedbackURL: URL? {
        guard let address = Secrets.feedbackEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "City Tourist beta feedback"),
            URLQueryItem(name: "body", value: "\n\n\nCity Tourist \(Self.version), iOS \(UIDevice.current.systemVersion)")
        ]
        return components.url
    }

    /// What the app sends where, including that videos are YouTube API Services.
    static let privacyURL = URL(string: "https://citytourist.pages.dev/privacy")!

    /// "1.0 (3)": the version and the build, so feedback says which one.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                    Text(L10n.text(title)).bodyStyle()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.vertical, 16)
                Hairline()
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog()).environment(AuthenticationStore()).environment(AvatarStore())
}
