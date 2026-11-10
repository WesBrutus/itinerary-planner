import Foundation

/// Kept separate from credentials: legacy state has no profile and decodes to these defaults.
struct UserProfile: Codable, Equatable {
    var displayName: String = ""
    var language: AppLanguage = .device
    var distanceUnit: DistanceUnit = .automatic
    /// What the traveller picked in onboarding. Optional so profiles saved
    /// before onboarding existed still decode.
    var interests: [PlaceCategory]?
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case device, en, es, fr, pt, de, it, ja
    case zhHans = "zh-Hans"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .device: L10n.text("Device language")
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        case .pt: "Português"
        case .de: "Deutsch"
        case .it: "Italiano"
        case .ja: "日本語"
        case .zhHans: "简体中文"
        }
    }
    var locale: Locale { self == .device ? .autoupdatingCurrent : Locale(identifier: rawValue) }
}

enum L10n {
    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "displayLanguage") ?? "device") ?? .device
    }
    static var locale: Locale { language.locale }
    /// The app's language by its English name, "Spanish", for telling a model
    /// which language to write in.
    static var languageName: String {
        Locale(identifier: "en").localizedString(forIdentifier: resourceCode(for: locale)) ?? "English"
    }
    static func resourceCode(for locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        if code == "zh" {
            // Traditional Chinese uses English until a dedicated translation is available.
            return locale.language.script?.identifier == "Hant" ? "en" : "zh-Hans"
        }
        return ["en", "es", "fr", "pt", "de", "it", "ja"].contains(code) ? code : "en"
    }
    static var bundle: Bundle {
        let code = resourceCode(for: locale)
        return Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
    static func text(_ key: String, locale: Locale = L10n.locale) -> String {
        let code = resourceCode(for: locale)
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let english = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let fallback = english.localizedString(forKey: key, value: key, table: nil)
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case automatic, metric, imperial
    var id: String { rawValue }
    var title: String {
        L10n.text(self == .automatic ? "Device units" : self == .metric ? "Kilometers (km)" : "Miles (mi)")
    }
    func resolved(locale: Locale) -> DistanceUnit {
        self == .automatic ? (locale.measurementSystem == .metric ? .metric : .imperial) : self
    }
}

/// All calculations and API radii remain meters. Preferences only affect presentation/input.
enum DistanceFormatting {
    static let metersPerMile = 1609.344
    static func meters(_ value: Double, unit: DistanceUnit, locale: Locale = .autoupdatingCurrent) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        return value * (unit.resolved(locale: locale) == .imperial ? metersPerMile : 1000)
    }
    static func value(meters: Double, unit: DistanceUnit, locale: Locale = .autoupdatingCurrent) -> Double {
        guard meters.isFinite, meters >= 0 else { return 0 }
        return meters / (unit.resolved(locale: locale) == .imperial ? metersPerMile : 1000)
    }
    static func string(meters: Double, unit: DistanceUnit, locale: Locale = .autoupdatingCurrent) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }
        let suffix = unit.resolved(locale: locale) == .imperial ? "mi" : "km"
        return "\(value(meters: meters, unit: unit, locale: locale).formatted(.number.locale(locale).precision(.fractionLength(1)))) \(suffix)"
    }
}

extension Coordinate {
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// A corrupt entry must not discard the other events in an otherwise valid page.
struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}
