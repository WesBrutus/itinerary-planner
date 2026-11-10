import AuthenticationServices
import SwiftUI

/// Log in or sign up with a phone number or Apple. One path serves both: the
/// account is created the first time someone continues. Shown in the Profile
/// sheet and as a step of onboarding.
struct AccountAccessView: View {
    @Environment(AuthenticationStore.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var country = PhoneCountry.supported[0]
    @State private var number = ""
    @State private var code = ""
    @State private var nonce = AppleNonce.make()
    @State private var shakes = 0
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if auth.pendingPhone == nil {
                phoneEntry.transition(stepTransition(from: .leading))
            } else {
                codeEntry.transition(stepTransition(from: .trailing))
            }
            if let message = auth.errorMessage {
                Label(L10n.text(message), systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Brand.rausch)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(reduceMotion ? nil : Animation.spring(response: 0.4, dampingFraction: 0.85), value: auth.pendingPhone)
        .animation(.easeOut(duration: 0.2), value: auth.errorMessage)
        .onChange(of: auth.errorMessage) { _, message in
            guard message != nil else { return }
            withAnimation(reduceMotion ? nil : Animation.linear(duration: 0.4)) { shakes += 1 }
        }
        .sensoryFeedback(.error, trigger: shakes)
        .sensoryFeedback(.impact(weight: .light), trigger: auth.pendingPhone)
    }

    private func stepTransition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    // MARK: Phone number

    private var phoneEntry: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    Menu {
                        Picker(L10n.text("Country code"), selection: $country) {
                            ForEach(PhoneCountry.supported) { country in
                                Text("\(country.name) (+\(country.dialCode))").tag(country)
                            }
                        }
                    } label: {
                        HStack {
                            field(label: "Country code") {
                                Text("\(country.name) (+\(country.dialCode))").bodyStyle()
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .padding(.trailing, 14)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                    field(label: "Phone number") {
                        TextField(L10n.text("Phone number"), text: $number)
                            .keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .onChange(of: number) { _, value in number = country.masked(value) }
                            .onChange(of: country) { _, country in number = country.masked(number) }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                        .strokeBorder(Palette.inkMuted, lineWidth: 1)
                }
                .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                Text(L10n.text("We’ll text you a six-digit code. Standard SMS rates may apply.")).captionStyle()
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = auth.remaining(at: context.date)
                PrimaryButton(title: seconds > 0 ? L10n.format("Resend in %d s", seconds) : "Continue",
                              isEnabled: country.e164(number) != nil && !auth.busy && seconds == 0) {
                    guard let phone = country.e164(number) else { return }
                    Task { await auth.request(phone: phone) }
                }
            }
            HStack(spacing: 16) {
                Hairline()
                Text(L10n.text("or")).captionStyle()
                Hairline()
            }
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName]
                request.nonce = AppleNonce.sha256(nonce)
            } onCompletion: { result in
                finishAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
            .disabled(auth.busy)
            .opacity(auth.busy ? 0.4 : 1)
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(label)).font(.footnote).foregroundStyle(Palette.inkMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        let usedNonce = nonce
        // A nonce is good for one attempt.
        nonce = AppleNonce.make()
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
                auth.appleSignInFailed()
                return
            }
            // Apple shares the name only on the first sign-in, so keep it then.
            var name = ""
            if let components = credential.fullName {
                name = PersonNameComponentsFormatter().string(from: components)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Task {
                await auth.signInWithApple(idToken: token, nonce: usedNonce)
                let appleName = String(name.prefix(80))
                if auth.session != nil, !appleName.isEmpty, store.profile.displayName.isEmpty {
                    var profile = store.profile
                    profile.displayName = appleName
                    store.updateProfile(profile)
                }
            }
        case .failure(let error):
            // Closing Apple's sheet is a choice, not an error to report.
            if (error as? ASAuthorizationError)?.code != .canceled { auth.appleSignInFailed() }
        }
    }

    // MARK: Code

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Enter the code")).sectionTitleStyle()
                Text(L10n.format("We texted a six-digit code to %@", auth.pendingPhone ?? "")).metaStyle()
            }
            CodeBoxes(code: code, isFocused: codeFocused)
                .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                .contentShape(Rectangle())
                .onTapGesture { codeFocused = true }
                .background {
                    // The real field: it takes the keyboard and the SMS autofill
                    // while the boxes show what was typed.
                    TextField(L10n.text("Verification code"), text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
                .onChange(of: code) { _, value in
                    let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if digits != value { code = digits; return }
                    if digits.count == 6 { Task { await auth.verify(code: digits) } }
                }
            PrimaryButton(title: "Verify and sign in", isEnabled: code.count == 6 && !auth.busy) {
                Task { await auth.verify(code: code) }
            }
            VStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = auth.remaining(at: context.date)
                    Button(seconds > 0 ? L10n.format("Resend in %d s", seconds) : L10n.text("Resend code")) {
                        guard let phone = auth.pendingPhone else { return }
                        code = ""
                        Task { await auth.request(phone: phone) }
                    }
                    .disabled(seconds > 0 || auth.busy)
                }
                Button(L10n.text("Change phone number")) { auth.changeNumber(); code = "" }
                    .disabled(auth.busy)
            }
            .font(.subheadline.weight(.semibold))
            .tint(Palette.ink)
            .frame(maxWidth: .infinity)
        }
        .onAppear { codeFocused = true }
        .onChange(of: auth.errorMessage) { _, message in
            // A rejected code is cleared so the next one can be typed straight away.
            if message != nil, code.count == 6 { code = ""; codeFocused = true }
        }
    }
}

/// Six boxes that fill as the code is typed; each digit pops into place.
private struct CodeBoxes: View {
    let code: String
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let digits = Array(code)
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                let isActive = isFocused && index == min(digits.count, 5)
                ZStack {
                    RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                        .fill(Palette.elevated)
                    RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                        .strokeBorder(isActive ? Palette.ink : Palette.hairline, lineWidth: isActive ? 2 : 1)
                    if index < digits.count {
                        Text(String(digits[index]))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .frame(height: 56)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: code)
        .accessibilityHidden(true)
    }
}

/// The Profile sheet: "Log in or sign up".
struct AccountSheet: View {
    @Environment(AuthenticationStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(L10n.text("Log in or sign up")).sectionTitleStyle()
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.text("Close"))
                }
                AccountAccessView()
                Link(destination: ProfileView.privacyURL) {
                    Text(L10n.text("By continuing you agree to our Privacy Policy."))
                        .font(.footnote).underline()
                        .foregroundStyle(Palette.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.canvas)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Metric.sheetRadius)
        .onChange(of: auth.session?.user.id) { _, id in if id != nil { dismiss() } }
        .onDisappear { auth.changeNumber() }
    }
}
