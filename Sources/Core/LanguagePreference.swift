import SwiftUI

/// The language choices exposed by FilterKit.
/// `system` follows the device's preferred language when it is supported;
/// otherwise FilterKit falls back to English.
enum LanguageSelection: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    var localizationKey: LocalizedStringKey {
        switch self {
        case .system: return "language.system"
        case .chinese: return "language.chinese"
        case .english: return "language.english"
        }
    }
}

/// Owns the app-wide language preference and publishes locale changes to SwiftUI.
/// A manual choice is persisted and takes precedence over the device language.
final class LanguagePreference: ObservableObject {
    @Published var selection: LanguageSelection {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "filterkit.language.selection"

    init(defaults: UserDefaults = .standard) {
        let savedValue = defaults.string(forKey: Self.storageKey)
        self.selection = savedValue.flatMap(LanguageSelection.init(rawValue:)) ?? .system
    }

    /// Locale passed to the root SwiftUI environment. Updating this value
    /// causes localized SwiftUI views, including the tab bar, to refresh.
    var locale: Locale {
        switch selection {
        case .system:
            return Self.supportedSystemLocale()
        case .chinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    private static func supportedSystemLocale() -> Locale {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        // FilterKit currently supports Simplified Chinese and English only.
        // All other system languages intentionally fall back to English.
        if preferredLanguage.lowercased().hasPrefix("zh") {
            return Locale(identifier: "zh-Hans")
        }
        return Locale(identifier: "en")
    }
}
