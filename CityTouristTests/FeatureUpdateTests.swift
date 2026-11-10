import Foundation
import Testing
import UIKit
@testable import CityTourist

struct PreferenceTests {
    @Test func distancesStayInMetersAndRespectTheOverride() {
        let us = Locale(identifier: "en_US"), es = Locale(identifier: "es_ES")
        #expect(abs(DistanceFormatting.meters(1, unit: .imperial) - 1609.344) < 0.001)
        #expect(DistanceFormatting.value(meters: 1000, unit: .metric) == 1)
        #expect(DistanceFormatting.string(meters: 1609.344, unit: .imperial, locale: us) == "1.0 mi")
        #expect(DistanceFormatting.string(meters: 1000, unit: .metric, locale: es) == "1,0 km")
        #expect(DistanceFormatting.string(meters: .nan, unit: .metric) == "—")
        #expect(DistanceFormatting.meters(-10, unit: .metric) == 0)
        #expect(DistanceUnit.automatic.resolved(locale: us) == .imperial)
        #expect(DistanceUnit.automatic.resolved(locale: es) == .metric)
    }
    @Test func localizedResourcesResolveWithoutChangingGlobalPreferences() {
        #expect(L10n.text("Profile", locale: Locale(identifier: "es")) == "Perfil")
        #expect(L10n.text("Relaxation & Wellness", locale: Locale(identifier: "es")) == "Relajación y bienestar")
        #expect(L10n.text("Profile", locale: Locale(identifier: "ko")) == "Profile")
    }
    @Test func wellnessTaxonomyIsIndoorAndOldCategoriesDecode() throws {
        for type in ["spa", "sauna", "wellness_center", "massage_spa", "yoga_studio"] {
            #expect(GooglePlacesService.category(fromTypes: [type, "establishment"], fallback: .activity) == .relaxation)
        }
        #expect(!PlaceCategory.relaxation.isOutdoors)
        #expect(try JSONDecoder().decode(PlaceCategory.self, from: Data(#""food""#.utf8)) == .food)
    }
    @Test func phoneInputIsMaskedAndValidated() {
        let us = PhoneCountry.supported[0]
        #expect(us.e164("202 555 0123") == "+12025550123")
        #expect(us.e164("1") == nil)
        #expect(us.e164("0202555012") == nil)
        #expect(us.masked("2025550123abc") == "202 555 012 3")
    }
    @Test func malformedAvatarIsRejected() {
        #expect(throws: (any Error).self) { try AvatarStore.compressed(Data("not an image".utf8)) }
    }
    @MainActor @Test func avatarIsDownsampledBeforeStorage() throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let jpeg = try AvatarStore.compressed(#require(original.pngData()))
        let decoded = try #require(UIImage(data: jpeg))
        #expect(decoded.size.width <= 512 && decoded.size.height <= 512)
        #expect(jpeg.count < 1_000_000)
    }
}

@MainActor struct ProfilePersistenceTests {
    @Test func legacyStateGetsDefaultPreferencesAndRetainsBookmarks() throws {
        let url = URL.temporaryDirectory.appending(path: "legacy-profile-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"trips":[],"savedPlaceIDs":["unknown-id"],"browsingCityID":"lisbon"}"#.utf8).write(to: url)
        let store = AppStore(storageURL: url)
        #expect(store.profile == UserProfile())
        #expect(store.savedPlaceIDs == ["unknown-id"])
        #expect(store.storageIssue == nil)
        let sections = SavedCityGroups().sections(store: store)
        #expect(sections.first?.id == "unknown")
        #expect(sections.first?.placeIDs == ["unknown-id"])
    }
    @Test func preferencesRoundTripWithoutReplacingTrips() throws {
        let url = URL.temporaryDirectory.appending(path: "profile-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: url, loadFromDisk: false)
        let trip = store.createTrip(city: SampleData.cities[0], start: .now, end: .now)
        store.updateProfile(UserProfile(displayName: "Test", language: .device, distanceUnit: .imperial))
        let restored = AppStore(storageURL: url)
        #expect(restored.trips.first?.id == trip.id)
        #expect(restored.profile.displayName == "Test")
        #expect(restored.profile.distanceUnit == .imperial)
    }
    @Test func unknownCityNeverBorrowsLisbonAndGroupsSortAlphabetically() throws {
        let url = URL.temporaryDirectory.appending(path: "groups-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: url, loadFromDisk: false)
        for name in ["Zurich", "Amsterdam"] {
            var city = SampleData.cities[0]; city.id = UUID().uuidString; city.name = name
            city.coordinate = Coordinate(latitude: -80, longitude: 0)
            CityDirectory.register(city)
            var place = SampleData.places[0]; place.id = UUID().uuidString; place.cityID = city.id
            PlaceDirectory.register([place]); store.toggleSaved(place)
        }
        var missing = SampleData.places[0]; missing.id = UUID().uuidString; missing.cityID = "not-a-real-city"
        PlaceDirectory.register([missing]); store.toggleSaved(missing)
        let groups = SavedCityGroups().sections(store: store)
        #expect(groups.count == 3)
        #expect(groups[0].title.hasPrefix("Amsterdam"))
        #expect(groups[1].title.hasPrefix("Zurich"))
        #expect(groups[2].id == "unknown")
    }
}

private struct FakeEvents: EventProvider {
    let providerID: String
    var result: EventPage?
    func page(query: EventQuery, cursor: String?) async throws -> EventPage {
        guard let result else { throw URLError(.timedOut) }
        return result
    }
}
struct EventAggregationTests {
    private func event(_ id: String, minute: Int = 600, name: String = "A Show") -> Place {
        var event = SampleData.places[0]; event.id = id; event.name = name
        event.event = EventInfo(ticketURL: nil, localDate: "2026-11-08", startMinute: minute,
                                venue: "Main Hall", kind: "Music", price: nil)
        return event
    }
    @Test func duplicatesCollapseButDifferentPerformancesRemain() {
        let places = EventAggregator.normalized([event("eb:2", name: "A SHOW!"), event("tm:1"), event("tm:3", minute: 800)])
        #expect(places.map(\.id) == ["tm:1", "tm:3"])
    }
    @Test func aFailedProviderPreservesOtherResultsAndItsRetryCursor() async {
        let query = EventQuery(center: SampleData.cities[0].coordinate, cityID: "lisbon", start: .now, end: .now)
        let service = EventAggregator(providers: [
            FakeEvents(providerID: "ticketmaster", result: EventPage(events: [event("tm:1")], nextCursor: "1")),
            FakeEvents(providerID: "eventbrite", result: nil)
        ])
        let feed = await service.next(EventFeed(query: query, cursors: ["eventbrite": "0:2"]))
        #expect(feed.events.map(\.id) == ["tm:1"])
        #expect(feed.cursors["ticketmaster"] == "1")
        #expect(feed.cursors["eventbrite"] == "0:2")
        #expect(feed.failed == ["eventbrite"])
        #expect(!feed.completed.contains("eventbrite"))
    }
    @Test func repeatedCursorStopsPaginationAndDuplicateIDsDoNotAccumulate() async {
        let query = EventQuery(center: SampleData.cities[0].coordinate, cityID: "lisbon", start: .now, end: .now)
        let service = EventAggregator(providers: [FakeEvents(providerID: "ticketmaster", result: EventPage(events: [event("tm:1")], nextCursor: "1"))])
        let feed = await service.next(EventFeed(query: query, events: [event("tm:1")], cursors: ["ticketmaster": "1"]))
        #expect(feed.events.count == 1)
        #expect(feed.completed.contains("ticketmaster"))
    }
}

private final class MemorySession: SessionStoring {
    var value: AuthSession?
    var shouldFail = false
    func read() throws -> AuthSession? { value }
    func write(_ session: AuthSession?) throws {
        if shouldFail { throw AccountError.secureStorage }
        value = session
    }
}
private actor FakePhoneAuth: PhoneAuthServing {
    var requests = 0, refreshes = 0
    let error: AccountError?
    init(error: AccountError? = nil) { self.error = error }
    func requestCode(phone: String) async throws { requests += 1; if let error { throw error } }
    func verify(phone: String, code: String) async throws -> AuthSession {
        if let error { throw error }
        return Self.session
    }
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        if let error { throw error }
        return Self.session
    }
    func refresh(token: String) async throws -> AuthSession {
        refreshes += 1
        try await Task.sleep(for: .milliseconds(30))
        return Self.session
    }
    func logout(accessToken: String) async throws {}
    static var session: AuthSession {
        AuthSession(access_token: "access", refresh_token: "refresh", expires_in: 3600,
                    expires_at: Date.now.timeIntervalSince1970 + 3600, user: .init(id: UUID(), phone: "12025550123"))
    }
}
@MainActor struct PhoneLifecycleTests {
    @Test func requestsRespectCooldownAndVerificationHandsOffSession() async {
        let fake = FakePhoneAuth(), storage = MemorySession()
        let auth = AuthenticationStore(service: fake, storage: storage)
        await auth.request(phone: "+12025550123")
        await auth.request(phone: "+12025550123")
        #expect(await fake.requests == 1)
        #expect(auth.remaining(at: .now.addingTimeInterval(61)) == 0)
        await auth.verify(code: "123456")
        #expect(auth.session != nil && storage.value == auth.session)
        #expect(auth.pendingPhone == nil)
        await auth.signOut()
        #expect(auth.session == nil && storage.value == nil)
    }
    @Test func timeoutStillAllowsVerificationAndRateLimitExtendsDeadline() async {
        let timedOut = AuthenticationStore(service: FakePhoneAuth(error: .network), storage: MemorySession())
        await timedOut.request(phone: "+12025550123")
        #expect(timedOut.pendingPhone == "+12025550123")
        #expect(timedOut.remaining(at: .now) > 0 && timedOut.errorMessage != nil)
        let limited = AuthenticationStore(service: FakePhoneAuth(error: .rateLimited(120)), storage: MemorySession())
        await limited.request(phone: "+12025550123")
        #expect(limited.remaining(at: .now) > 60)
    }
    @Test func invalidCodeAndFailedKeychainNeverEstablishSession() async {
        let storage = MemorySession(); storage.shouldFail = true
        let auth = AuthenticationStore(service: FakePhoneAuth(), storage: storage)
        await auth.request(phone: "+12025550123")
        await auth.verify(code: "abc123")
        #expect(auth.session == nil)
        await auth.verify(code: "123456")
        #expect(auth.session == nil && auth.errorMessage != nil)
    }
    @Test func appleSignInStoresTheSessionAndRejectionsNeverDo() async {
        let storage = MemorySession()
        let auth = AuthenticationStore(service: FakePhoneAuth(), storage: storage)
        await auth.signInWithApple(idToken: "token", nonce: "nonce")
        #expect(auth.session != nil && storage.value == auth.session)
        let rejected = AuthenticationStore(service: FakePhoneAuth(error: .expiredCode), storage: MemorySession())
        await rejected.signInWithApple(idToken: "token", nonce: "nonce")
        #expect(rejected.session == nil)
        #expect(rejected.errorMessage == AccountError.appleRejected.localizedDescription)
    }
    @Test func appleNonceIsRandomAndHashedAsAppleExpects() {
        #expect(AppleNonce.make().count == 32 && AppleNonce.make() != AppleNonce.make())
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    @Test func concurrentTokenRequestsShareOneRefresh() async throws {
        let storage = MemorySession(); var session = FakePhoneAuth.session; session.expires_at = 0; storage.value = session
        let fake = FakePhoneAuth(), auth = AuthenticationStore(service: nil, storage: MemorySession())
        #expect(!auth.isConfigured)
        let account = AuthenticationStore(service: fake, storage: storage)
        async let first = account.accessToken()
        async let second = account.accessToken()
        let results = try await [first, second]
        #expect(results == ["access", "access"])
        #expect(await fake.refreshes == 1)
    }
}

extension PlacesAPITests {
    @Test func smsTransportUsesSupabaseAndHandlesExpiredCodes() async throws {
        StubURLProtocol.reset(); StubURLProtocol.respond(json: "{}")
        let service = SupabasePhoneService(configuration: SupabaseConfiguration(url: URL(string: "https://example.supabase.co")!, publicKey: "public-test"), session: StubURLProtocol.makeSession())
        try await service.requestCode(phone: "+12025550123")
        #expect(StubURLProtocol.recorded.first?.url?.path == "/auth/v1/otp")
        #expect(StubURLProtocol.recorded.first?.value(forHTTPHeaderField: "apikey") == "public-test")
        #expect(StubURLProtocol.recorded.first?.stubBody?["phone"] as? String == "+12025550123")
        StubURLProtocol.respond(status: 403, json: #"{"error_code":"otp_expired"}"#)
        await #expect(throws: AccountError.self) { try await service.verify(phone: "+12025550123", code: "123456") }
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"7F0C1C9E-6C0B-4C5B-9C55-0C6E0C1D2E3F","email":"traveler@example.com"}}"#)
        let apple = try await service.signInWithApple(idToken: "identity", nonce: "raw")
        #expect(apple.user.email == "traveler@example.com" && apple.user.phone == nil)
        #expect(StubURLProtocol.recorded.first?.url?.query == "grant_type=id_token")
        #expect(StubURLProtocol.recorded.first?.stubBody?["provider"] as? String == "apple")
        #expect(StubURLProtocol.recorded.first?.stubBody?["nonce"] as? String == "raw")
    }
    @Test func ticketmasterPaginationFollowsMetadata() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"_embedded":{"events":[]},"page":{"totalPages":3}}"#)
        let service = TicketmasterService(apiKey: "test", session: StubURLProtocol.makeSession())
        let query = EventQuery(center: SampleData.cities[0].coordinate, cityID: "lisbon", start: .now, end: .now)
        let page = try await service.page(query: query, cursor: "1")
        #expect(page.nextCursor == "2")
        #expect(StubURLProtocol.recorded.first?.url?.query?.contains("page=1") == true)
    }
    @MainActor @Test func eventbriteStopsRestoreThroughTheirProviderAndRejectUnsafeLinks() async throws {
        StubURLProtocol.reset()
        let id = String(Int.random(in: 100000...999999))
        StubURLProtocol.respond(json: """
        {"events":[{"id":"\(id)","name":"Wellness fair","localDate":"2026-11-08","startMinute":600,
        "venue":"Hall","latitude":38.7,"longitude":-9.1,"ticketURL":"javascript:alert(1)","imageURL":null}],"nextCursor":"0:2"}
        """)
        let service = EventbriteService(endpoint: URL(string: "https://example.supabase.co/functions/v1/eventbrite")!, session: StubURLProtocol.makeSession())
        let catalog = PlaceCatalog(makeService: { nil }, makeEventService: { nil }, makeEventbriteService: { service })
        await catalog.resolve(["eb:\(id)"], cityID: "lisbon")
        let event = try #require(PlaceDirectory.place(id: "eb:\(id)"))
        #expect(event.isEvent && event.eventProvider == "Eventbrite")
        #expect(event.event?.ticketURL == nil)
        #expect(StubURLProtocol.recorded.first?.url?.query == "id=\(id)")
    }
}

extension PlacesAPITests {
    @Test func malformedEventsDoNotDiscardHealthySiblings() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: """
        {"_embedded":{"events":[{"id":3,"name":false},\(TicketmasterFixtures.event(id: "healthy"))]}}
        """)
        let service = TicketmasterService(apiKey: "test", session: StubURLProtocol.makeSession())
        let result = try await service.events(near: SampleData.cities[0].coordinate, cityID: "lisbon", from: .now, to: .now)
        #expect(result.map(\.id) == ["tm:healthy"])
    }
}

struct AdditionalLanguageTests {
    @Test func regionalLocalesResolveAndUnsupportedLanguagesFallBack() {
        #expect(L10n.resourceCode(for: Locale(identifier: "fr_CA")) == "fr")
        #expect(L10n.resourceCode(for: Locale(identifier: "pt_BR")) == "pt")
        #expect(L10n.resourceCode(for: Locale(identifier: "zh_CN")) == "zh-Hans")
        #expect(L10n.resourceCode(for: Locale(identifier: "zh_TW")) == "en")
        #expect(L10n.resourceCode(for: Locale(identifier: "ko")) == "en")
    }
    @Test func everyAdditionalLanguageHasLocalizedProfileResources() {
        for (code, title) in [("fr", "Profil"), ("pt", "Perfil"), ("de", "Profil"), ("it", "Profilo"), ("ja", "プロフィール"), ("zh-Hans", "个人资料")] {
            #expect(L10n.text("Profile", locale: Locale(identifier: code)) == title)
        }
        #expect(L10n.text("Weather.Clear", locale: Locale(identifier: "fr")) == "Dégagé")
        #expect(L10n.text("Weather.Clear", locale: Locale(identifier: "ko")) == "Clear",
                "a language without its own file reads the English value, not the key")
    }

    /// A string added in English has to arrive in every language with it, with
    /// the same values to fill in, or that screen turns up half-translated.
    @Test func everyLanguageTranslatesEveryEnglishString() throws {
        func strings(_ code: String) throws -> [String: String] {
            let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                     inDirectory: nil, forLocalization: code))
            return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        }
        func placeholders(_ text: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(@|lld|d)"#)
            let range = NSRange(text.startIndex..., in: text)
            return pattern.matches(in: text, range: range)
                .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }.sorted()
        }
        let english = try strings("en")
        for code in ["es", "fr", "de", "it", "pt", "ja", "zh-Hans"] {
            let translated = try strings(code)
            let missing = english.keys.filter { translated[$0] == nil }.sorted()
            #expect(missing.isEmpty, "\(code) is missing \(missing.count): \(missing.prefix(3))")
            for (key, value) in translated where english[key] != nil {
                #expect(placeholders(key) == placeholders(value), "\(code): \(key)")
            }
        }
    }
}

struct WellnessRelevanceTests {
    @Test func unrelatedAndMissingTypesCannotBecomeWellnessByFallback() {
        for types in [[], ["establishment"], ["restaurant"], ["gym"], ["hospital"], ["beauty_salon"], ["park"]] {
            #expect(!GooglePlacesService.isWellness(types: types))
            #expect(GooglePlacesService.category(fromTypes: types, fallback: .relaxation) != .relaxation)
        }
    }
}

extension PlacesAPITests {
    @Test func wellnessSearchDropsUnrelatedProviderResults() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.nearbyLisbon)
        let service = GooglePlacesService(apiKey: "test", session: StubURLProtocol.makeSession())
        let results = try await service.nearby(city: SampleData.cities[0], category: .relaxation)
        #expect(results.isEmpty)
        let types = StubURLProtocol.recorded.first?.stubBody?["includedTypes"] as? [String]
        #expect(types?.contains("spa") == true)
        #expect(types?.contains("wellness_center") == true)
    }
}
