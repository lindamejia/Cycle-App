import Foundation

/// Calendar-day helpers. Day keys are local "yyyy-MM-dd" strings.
enum Day {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2 // weeks start on Monday
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String {
        keyFormatter.timeZone = .current
        return keyFormatter.string(from: date)
    }

    static func date(_ key: String) -> Date? {
        keyFormatter.timeZone = .current
        return keyFormatter.date(from: key).map { start($0) }
    }

    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static var today: Date { start(Date()) }

    static func add(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Whole days from a to b (b minus a).
    static func between(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: start(a), to: start(b)).day ?? 0
    }

    static func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? start(date)
    }

    static func at(_ hour: Int, _ minute: Int = 0, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func hour(_ date: Date) -> Int { calendar.component(.hour, from: date) }

    /// 1 = Monday ... 7 = Sunday
    static func isoWeekday(_ date: Date) -> Int {
        let w = calendar.component(.weekday, from: date) // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    static func display(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }
}

extension Double {
    /// 6.08 -> "6h 05m"
    var hoursMinutes: String {
        let total = Int((self * 60).rounded())
        return String(format: "%ldh %02ldm", total / 60, total % 60)
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    let m = s.count / 2
    return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
}

func mean(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
}

func standardDeviation(_ values: [Double]) -> Double? {
    guard values.count > 1, let m = mean(values) else { return nil }
    let v = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
    return v.squareRoot()
}
