import Foundation

/// Values to fill in before a TestFlight build. See README, "Configure the app".
enum Config {
    /// Supabase project URL, e.g. https://abcd1234.supabase.co
    static let supabaseURL = "https://YOUR-PROJECT.supabase.co"
    /// Supabase anon (public) key. Safe to ship: row-level security protects the data.
    static let supabaseAnonKey = "YOUR-SUPABASE-ANON-KEY"
    /// Shown in Settings and linked from the consent screen.
    static let privacyPolicyURL = URL(string: "https://example.com/privacy")!

    static let consentVersion = "2026-10-v1"
    static let trialLengthDays = 21
    static let experimentUnlockDay = 8
    static let experimentLengthDays = 10
    static let backfillDays = 90
    /// Days of history sent in each weekly summary (8 weeks).
    static let summaryDays = 56
    static let notificationWeeklyCap = 4

    static var isBackendConfigured: Bool {
        !supabaseURL.contains("YOUR-PROJECT") && !supabaseAnonKey.hasPrefix("YOUR-")
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }
}
