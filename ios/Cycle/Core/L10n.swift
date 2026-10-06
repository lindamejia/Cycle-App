import Foundation

/// Looks up a key in Localizable.strings (en / es, following the device language).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Looks up a format key and fills in its arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

enum AppLanguage {
    /// "es" when the app is running in Spanish, otherwise "en". Sent to the insight engine.
    static var code: String {
        (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("es") ? "es" : "en"
    }
}
