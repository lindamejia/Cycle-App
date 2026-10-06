import Foundation

struct DayForecast {
    var risk: Risk
    var headline: String
    var reasons: [String]
    var hasData: Bool

    /// "Likely a lower-energy day: 6h sleep, late luteal phase, 4 events."
    var sentence: String {
        reasons.isEmpty ? headline + "." : headline + ": " + reasons.joined(separator: ", ") + "."
    }
}

/// On-device, rule-based forecast for the Today card (and the demo week forecast).
/// The weekly AI insight produces its own 7-day forecast, used for heads-up notifications.
enum ForecastEngine {
    static func forecast(for f: DayFeatures, baselines: Baselines, includeBody: Bool = true) -> DayForecast {
        var score = 0
        var reasons: [(weight: Int, text: String)] = []

        if includeBody, let s = f.sleepHours {
            if s < 6.5 {
                score += 2
                reasons.append((3, L("forecast.reason.sleep", s.hoursShort)))
            } else if let b = baselines.sleep, s < b - 0.75 {
                score += 1
                reasons.append((2, L("forecast.reason.sleep", s.hoursShort)))
            }
        }
        if includeBody, let h = f.hrv, let b = baselines.hrv, h < b * 0.85 {
            score += 1
            reasons.append((1, L("forecast.reason.hrv")))
        }
        if includeBody, let r = f.restingHR, let b = baselines.restingHR, r > b + 3 {
            score += 1
            reasons.append((1, L("forecast.reason.rhr")))
        }
        if let phase = f.phase {
            if phase == .lateLuteal {
                score += 1
                reasons.append((2, L("forecast.reason.lateLuteal")))
            } else if phase == .menstrual, let d = f.cycleDay, d <= 2 {
                score += 1
                reasons.append((2, L("forecast.reason.period", d)))
            }
        }
        if f.eventCount >= 4 || f.scheduledHours >= 5 {
            score += 1
            reasons.append((2, L("forecast.reason.events", f.eventCount)))
        }
        if f.lateEvents > 0 {
            score += 1
            reasons.append((1, L("forecast.reason.late")))
        } else if f.eveningEvents > 0 && f.eventCount >= 3 {
            score += 1
            reasons.append((1, L("forecast.reason.evening")))
        }

        let hasData = f.sleepHours != nil || f.hrv != nil || f.phase != nil || f.eventCount > 0
        let risk: Risk = score >= 4 ? .high : score >= 2 ? .med : .low
        let headline: String
        if !hasData {
            headline = L("forecast.headline.nodata")
        } else {
            switch risk {
            case .high: headline = L("forecast.headline.high")
            case .med: headline = L("forecast.headline.med")
            case .low: headline = L("forecast.headline.low")
            }
        }
        let top = reasons.sorted { $0.weight > $1.weight }.prefix(3).map(\.text)
        return DayForecast(risk: risk, headline: headline, reasons: Array(top), hasData: hasData)
    }
}

extension Double {
    /// 6.0 -> "6h", 6.5 -> "6.5h"
    var hoursShort: String {
        let r = (self * 2).rounded() / 2
        return r == r.rounded() ? String(format: "%.0fh", r) : String(format: "%.1fh", r)
    }
}
