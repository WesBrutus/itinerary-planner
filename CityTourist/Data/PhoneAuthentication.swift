import CryptoKit
import Foundation
import Observation
import Security

struct PhoneCountry: Identifiable, Hashable {
    let id: String
    let name: String
    let dialCode: String
    let lengths: ClosedRange<Int>
    static let supported: [PhoneCountry] = [
        .init(id: "US", name: "United States / Canada", dialCode: "1", lengths: 10...10),
        .init(id: "GB", name: "United Kingdom", dialCode: "44", lengths: 10...10),
        .init(id: "ES", name: "España", dialCode: "34", lengths: 9...9),
        .init(id: "PT", name: "Portugal", dialCode: "351", lengths: 9...9),
        .init(id: "FR", name: "France", dialCode: "33", lengths: 9...9),
        .init(id: "DE", name: "Deutschland", dialCode: "49", lengths: 10...11),
        .init(id: "BR", name: "Brasil", dialCode: "55", lengths: 10...11),
        .init(id: "MX", name: "México", dialCode: "52", lengths: 10...10),
        .init(id: "HT", name: "Haïti", dialCode: "509", lengths: 8...8),
        .init(id: "IN", name: "India", dialCode: "91", lengths: 10...10),
        .init(id: "AU", name: "Australia", dialCode: "61", lengths: 9...9)
    ]
    func e164(_ input: String) -> String? {
        let digits = input.filter { $0.isASCII && $0.isNumber }
        guard lengths.contains(digits.count), !digits.hasPrefix("0"), digits.count + dialCode.count <= 15 else { return nil }
        return "+\(dialCode)\(digits)"
    }
    func masked(_ input: String) -> String {
        let digits = Array(input.filter { $0.isASCII && $0.isNumber }.prefix(lengths.upperBound))
        return stride(from: 0, to: digits.count, by: 3).map {
            String(digits[$0..<min($0 + 3, digits.count)])
        }.joined(separator: " ")
    }
}

struct AuthSession: Codable, Equatable {
    struct User: Codable, Equatable { let id: UUID; let phone: String?; var email: String? = nil }
    let access_token: String
    let refresh_token: String
    let expires_in: TimeInterval
    var expires_at: TimeInterval?
    let user: User
    var expiresAt: Date { Date(timeIntervalSince1970: expires_at ?? 0) }
}

enum AccountError: LocalizedError {
    case unavailable, invalidPhone, invalidCode, expiredCode, rateLimited(Int), network, server, secureStorage, appleRejected
    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.text("Phone sign-in is not configured yet.")
        case .invalidPhone: L10n.text("Enter a valid phone number without the country code or leading zero.")
        case .invalidCode: L10n.text("Enter the six-digit code from your text message.")
        case .expiredCode: L10n.text("That code is invalid or expired. Try again or request a new code.")
        case .rateLimited: L10n.text("Too many attempts. Please wait before trying again.")
        case .network: L10n.text("Could not connect. Check your connection and try again.")
        case .server: L10n.text("Sign-in is temporarily unavailable. Please try again.")
        case .secureStorage: L10n.text("Your session could not be saved securely. Please try again.")
        case .appleRejected: L10n.text("Apple sign-in could not be completed. Please try again.")
        }
    }
}

struct SupabaseConfiguration {
    let url: URL
    let publicKey: String
    static var current: Self? {
        guard let raw = Secrets.supabaseURL, let url = URL(string: raw), url.scheme == "https", url.host != nil,
              let key = Secrets.supabasePublishableKey else { return nil }
        return Self(url: url, publicKey: key)
    }
}

/// Apple signs the hashed nonce into its token; Supabase checks it against the raw one.
enum AppleNonce {
    static func make(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var generator = SystemRandomNumberGenerator()
        return String((0..<max(16, length)).map { _ in characters.randomElement(using: &generator) ?? "0" })
    }
    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

protocol PhoneAuthServing {
    func requestCode(phone: String) async throws
    func verify(phone: String, code: String) async throws -> AuthSession
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession
    func refresh(token: String) async throws -> AuthSession
    func logout(accessToken: String) async throws
}

struct SupabasePhoneService: PhoneAuthServing {
    let configuration: SupabaseConfiguration
    var session: URLSession = .shared

    func requestCode(phone: String) async throws {
        _ = try await request("otp", body: ["phone": phone, "create_user": true])
    }
    func verify(phone: String, code: String) async throws -> AuthSession {
        try decode(try await request("verify", body: ["phone": phone, "token": code, "type": "sms"]))
    }
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        try decode(try await request("token", query: "id_token",
                                     body: ["provider": "apple", "id_token": idToken, "nonce": nonce]))
    }
    func refresh(token: String) async throws -> AuthSession {
        try decode(try await request("token", query: "refresh_token", body: ["refresh_token": token]))
    }
    func logout(accessToken: String) async throws {
        _ = try await request("logout", body: [:], accessToken: accessToken)
    }
    private func decode(_ data: Data) throws -> AuthSession {
        var result = try JSONDecoder().decode(AuthSession.self, from: data)
        guard !result.access_token.isEmpty, !result.refresh_token.isEmpty,
              result.expires_in.isFinite, result.expires_in > 0 else { throw AccountError.server }
        if result.expires_at == nil { result.expires_at = Date.now.timeIntervalSince1970 + result.expires_in }
        return result
    }
    private func request(_ path: String, query: String? = nil, body: [String: Any], accessToken: String? = nil) async throws -> Data {
        var components = URLComponents(url: configuration.url.appending(path: "auth/v1/\(path)"), resolvingAgainstBaseURL: false)
        if let query { components?.queryItems = [URLQueryItem(name: "grant_type", value: query)] }
        guard let url = components?.url else { throw AccountError.unavailable }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw AccountError.network }
        guard let http = response as? HTTPURLResponse else { throw AccountError.server }
        if http.statusCode == 429 {
            let seconds = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            throw AccountError.rateLimited(min(3600, max(1, seconds)))
        }
        if [400, 401, 403, 422].contains(http.statusCode) { throw AccountError.expiredCode }
        guard (200..<300).contains(http.statusCode) else { throw AccountError.server }
        return data
    }
}

protocol SessionStoring {
    func read() throws -> AuthSession?
    func write(_ session: AuthSession?) throws
}
struct KeychainSessionStore: SessionStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.citytourist.auth",
         kSecAttrAccount as String: "session"]
    }
    func read() throws -> AuthSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AccountError.secureStorage }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }
    func write(_ session: AuthSession?) throws {
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.secureStorage }
            return
        }
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AccountError.secureStorage }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AccountError.secureStorage }
    }
}

@MainActor @Observable
final class AuthenticationStore {
    private(set) var session: AuthSession?
    private(set) var pendingPhone: String?
    private(set) var resendAvailableAt = Date.distantPast
    private(set) var busy = false
    var errorMessage: String?
    private let service: (any PhoneAuthServing)?
    private let storage: any SessionStoring
    private var refreshing: Task<AuthSession, Error>?
    var isConfigured: Bool { service != nil }

    init(service: (any PhoneAuthServing)? = SupabaseConfiguration.current.map { SupabasePhoneService(configuration: $0) },
         storage: any SessionStoring = KeychainSessionStore()) {
        self.service = service; self.storage = storage
        do { session = try storage.read() } catch { errorMessage = AccountError.secureStorage.localizedDescription }
    }
    func remaining(at date: Date) -> Int { max(0, Int(ceil(resendAvailableAt.timeIntervalSince(date)))) }
    func request(phone: String) async {
        guard !busy, remaining(at: .now) == 0 else { return }
        guard phone.range(of: #"^\+[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil else {
            errorMessage = AccountError.invalidPhone.localizedDescription; return
        }
        guard let service else { errorMessage = AccountError.unavailable.localizedDescription; return }
        busy = true; errorMessage = nil
        defer { busy = false }
        // Start cooldown even on a timeout: the server may already have sent the SMS.
        resendAvailableAt = .now.addingTimeInterval(60)
        pendingPhone = phone
        do { try await service.requestCode(phone: phone) }
        catch { handle(error) }
    }
    func verify(code: String) async {
        guard !busy, let phone = pendingPhone, let service else { return }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            errorMessage = AccountError.invalidCode.localizedDescription; return
        }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let verified = try await service.verify(phone: phone, code: code)
            try storage.write(verified)
            session = verified; pendingPhone = nil
        } catch { handle(error) }
    }
    func signInWithApple(idToken: String, nonce: String) async {
        guard !busy else { return }
        guard let service else { errorMessage = AccountError.unavailable.localizedDescription; return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let verified = try await service.signInWithApple(idToken: idToken, nonce: nonce)
            try storage.write(verified)
            session = verified; pendingPhone = nil
        } catch AccountError.expiredCode {
            // The shared transport reports any rejected credential as an expired code.
            errorMessage = AccountError.appleRejected.localizedDescription
        } catch { handle(error) }
    }
    func appleSignInFailed() { errorMessage = AccountError.appleRejected.localizedDescription }
    /// A single refresh is shared by concurrent avatar/API requests.
    func accessToken() async throws -> String {
        guard let session, let service else { throw AccountError.unavailable }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.access_token }
        if let refreshing { return try await refreshing.value.access_token }
        let task = Task { try await service.refresh(token: session.refresh_token) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let renewed = try await task.value
            try storage.write(renewed); self.session = renewed
            return renewed.access_token
        } catch {
            if case AccountError.expiredCode = error {
                try storage.write(nil); self.session = nil
            }
            handle(error); throw error
        }
    }
    func restoreSession() async {
        guard session != nil else { return }
        _ = try? await accessToken()
    }
    func signOut() async {
        guard !busy, refreshing == nil else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            // Keep credentials on a server failure so logout can be retried.
            if session != nil, let service { try await service.logout(accessToken: accessToken()) }
            try storage.write(nil)
            session = nil; pendingPhone = nil
        } catch { handle(error) }
    }
    func changeNumber() { guard !busy else { return }; pendingPhone = nil; errorMessage = nil }
    private func handle(_ error: Error) {
        guard !(error is CancellationError) else { return }
        if case AccountError.rateLimited(let seconds) = error { resendAvailableAt = .now.addingTimeInterval(Double(seconds)) }
        errorMessage = (error as? AccountError ?? .server).localizedDescription
    }
}
