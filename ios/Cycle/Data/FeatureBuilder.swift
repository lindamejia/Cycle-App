import Foundation

/// Turns raw health + calendar data into one feature row per day.
enum FeatureBuilder {
    static func build(days: [Date], health: [String: HealthDay], eventsByDay: [String: [CalendarEvent]],
                      energy: [String: Int], cycle: CycleEstimator) -> [DayFeatures] {
        let temps = health.values.compactMap(\.wristTemp)
        let tempBaseline = median(temps)

        return days.map { day in
            let k = Day.key(day)
            let h = health[k]
            let timed = (eventsByDay[k] ?? []).filter { !$0.isAllDay }
            let cycleInfo = cycle.info(for: day)
            var tempDelta: Double?
            if let t = h?.wristTemp, let b = tempBaseline { tempDelta = t - b }

            return DayFeatures(
                date: k,
                sleepHours: h?.sleepHours,
                sleepEfficiency: h?.sleepEfficiency,
                hrv: h?.hrv,
                restingHR: h?.restingHR,
                steps: h?.steps,
                activeEnergy: h?.activeEnergy,
                workoutCount: h?.workoutCount ?? 0,
                workoutMinutes: h?.workoutMinutes ?? 0,
                wristTempDelta: tempDelta,
                flow: h?.flow ?? false,
                cycleDay: cycleInfo?.day,
                phase: cycleInfo?.phase,
                eventCount: timed.count,
                scheduledHours: timed.reduce(0) { $0 + min($1.durationMinutes, 12 * 60) } / 60,
                eveningEvents: timed.filter { (18..<22).contains(Day.hour($0.start)) }.count,
                lateEvents: timed.filter { isLate($0) }.count,
                energy: energy[k])
        }
    }

    /// Starts at or after 22:00 (or before 04:00), or runs past 23:00.
    static func isLate(_ e: CalendarEvent) -> Bool {
        let h = Day.hour(e.start)
        if h >= 22 || h < 4 { return true }
        return e.end > Day.at(23, on: e.start)
    }

    static func partOfDay(_ e: CalendarEvent) -> String {
        if e.isAllDay { return "all_day" }
        let h = Day.hour(e.start)
        switch h {
        case 4..<12: return "morning"
        case 12..<18: return "afternoon"
        case 18..<22: return "evening"
        default: return "late"
        }
    }
}

/// Personal baselines over the last 28 days, used by the on-device forecast.
struct Baselines {
    var sleep: Double?
    var hrv: Double?
    var restingHR: Double?

    init(features: [DayFeatures]) {
        let recent = features.suffix(29).dropLast() // exclude today
        sleep = median(recent.compactMap(\.sleepHours))
        hrv = median(recent.compactMap(\.hrv))
        restingHR = median(recent.compactMap(\.restingHR))
    }
}
