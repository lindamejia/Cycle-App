import Foundation

/// Realistic mock health + calendar data for the simulator and demos.
/// Deterministic: the same day always gets the same values. Today is set up as a
/// short-sleep, late-luteal, busy day so the forecast card has something to say.
final class DemoDataSource: HealthDataSource, CalendarDataSource {
    static let shared = DemoDataSource()

    static let cycleLength = 29
    /// Cycle day of today in the demo.
    static let todayCycleDay = 25

    var isAvailable: Bool { true }

    func requestAuthorization() async throws {}
    func requestAccess() async -> Bool { true }

    // MARK: Cycle

    func cycleDay(for date: Date) -> Int {
        let offset = Day.between(Day.today, date)
        let n = (Self.todayCycleDay - 1 + offset) % Self.cycleLength
        return (n + Self.cycleLength) % Self.cycleLength + 1
    }

    private func phaseFactor(_ cycleDay: Int) -> (luteal: Bool, lateLuteal: Bool, menstrual: Bool) {
        let ovulation = Self.cycleLength - 14
        return (cycleDay > ovulation + 1, cycleDay >= Self.cycleLength - 4, cycleDay <= 5)
    }

    // MARK: Health

    func healthDays(from: Date, to: Date) async -> [String: HealthDay] {
        var out: [String: HealthDay] = [:]
        var day = Day.start(from)
        let today = Day.today
        while day < to && day <= today {
            out[Day.key(day)] = health(on: day, isToday: day == today)
            day = Day.add(1, to: day)
        }
        return out
    }

    /// Simulated evening energy check-in (about 3 days in 5 answered).
    func energy(on day: Date) -> Int? {
        var rng = SeededRandom(seed: UInt64(("energy" + Day.key(day)).hashValueStable))
        guard rng.next() < 0.6 else { return nil }
        let h = health(on: day, isToday: false)
        let p = phaseFactor(cycleDay(for: day))
        var score = 2.0 + rng.normal() * 0.45
        if let s = h.sleepHours { score += (s - 7.0) * 0.8 }
        if p.lateLuteal { score -= 0.5 }
        if eventsForDay(day).filter({ !$0.isAllDay }).count >= 4 { score -= 0.35 }
        return min(3, max(1, Int(score.rounded())))
    }

    private func health(on day: Date, isToday: Bool) -> HealthDay {
        var rng = SeededRandom(seed: UInt64(Day.key(day).hashValueStable))
        let cd = cycleDay(for: day)
        let p = phaseFactor(cd)
        let weekday = Day.isoWeekday(day)
        let previous = Day.add(-1, to: day)
        let lateEveningBefore = eventsForDay(previous).contains { Day.hour($0.start) >= 19 && !$0.isAllDay }

        var sleep = 7.25 + rng.normal() * 0.45
        if weekday >= 6 { sleep += 0.4 }
        if lateEveningBefore { sleep -= 0.8 }
        if p.lateLuteal { sleep -= 0.35 }
        if p.menstrual && cd <= 2 { sleep -= 0.25 }
        sleep = min(max(sleep, 4.8), 9.2)

        var h = HealthDay()
        h.sleepHours = isToday ? 6.0 : sleep
        h.sleepEfficiency = min(0.97, max(0.78, 0.9 + rng.normal() * 0.03 - (lateEveningBefore ? 0.03 : 0)))

        var hrv = 49 + rng.normal() * 5 + (sleep - 7.2) * 4
        if p.luteal { hrv -= 5 }
        if p.lateLuteal { hrv -= 4 }
        h.hrv = isToday ? 38 : max(22, hrv)

        var rhr = 58 + rng.normal() * 1.5 - (sleep - 7.2) * 1.2
        if p.luteal { rhr += 2.5 }
        h.restingHR = isToday ? 62 : rhr

        h.steps = max(1800, 7800 + rng.normal() * 2600 + (weekday >= 6 ? 1500 : 0))
        h.activeEnergy = max(120, (h.steps ?? 6000) * 0.045 + rng.normal() * 60)
        let works = [2, 4, 6].contains(weekday) && rng.next() < 0.75
        h.workoutCount = works ? 1 : 0
        h.workoutMinutes = works ? 35 + rng.normal() * 8 : 0
        h.wristTemp = 34.6 + (p.luteal ? 0.32 : 0) + rng.normal() * 0.08
        h.flow = p.menstrual
        return h
    }

    // MARK: Calendar

    func events(from: Date, to: Date) -> [CalendarEvent] {
        var out: [CalendarEvent] = []
        var day = Day.start(from)
        while day < to {
            out += eventsForDay(day)
            day = Day.add(1, to: day)
        }
        return out
    }

    private static let meetings = [
        "Team standup", "1:1 with Laura", "Product review", "Client call", "Quarterly planning",
        "Design critique", "Hiring interview", "Budget sync", "Roadmap workshop", "All hands",
    ]
    private static let evenings = [
        "Dinner with Marta", "Birthday drinks", "Pilates", "Yoga class", "Concert",
        "Book club", "Late show", "Wine bar with friends",
    ]
    private static let weekend = ["Brunch", "Run club", "Pottery class", "Market", "Flight to Lisbon"]

    func eventsForDay(_ day: Date) -> [CalendarEvent] {
        var rng = SeededRandom(seed: UInt64(("cal" + Day.key(day)).hashValueStable))
        let weekday = Day.isoWeekday(day)
        var out: [CalendarEvent] = []
        func add(_ title: String, _ h: Int, _ m: Int, _ minutes: Int) {
            let start = Day.at(h, m, on: day)
            out.append(CalendarEvent(title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: false))
        }

        if day == Day.today {
            add("Team standup", 9, 30, 15)
            add("Product review", 11, 0, 60)
            add("Client call", 14, 0, 45)
            add("Roadmap workshop", 16, 0, 90)
            return out
        }

        if weekday <= 5 {
            let count = 1 + Int(rng.next() * 5)
            let hours = [9, 10, 11, 12, 14, 15, 16, 17].shuffledStable(&rng)
            for i in 0..<count {
                let title = Self.meetings[Int(rng.next() * Double(Self.meetings.count))]
                add(title, hours[i], rng.next() < 0.5 ? 0 : 30, [30, 45, 60, 90][Int(rng.next() * 4)])
            }
        } else if rng.next() < 0.7 {
            add(Self.weekend[Int(rng.next() * Double(Self.weekend.count))], 11, 0, 120)
        }
        if rng.next() < (weekday >= 4 ? 0.45 : 0.2) {
            let title = Self.evenings[Int(rng.next() * Double(Self.evenings.count))]
            let late = title == "Late show" || title == "Wine bar with friends"
            add(title, late ? 22 : 19, late ? 0 : 30, late ? 150 : 120)
        }
        return out
    }
}

// MARK: - Deterministic randomness

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// Uniform in [0, 1).
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }

    /// Roughly standard normal.
    mutating func normal() -> Double {
        (0..<6).reduce(0.0) { acc, _ in acc + next() } - 3.0
    }
}

extension String {
    /// Stable across launches (Swift's hashValue is randomly seeded per process).
    var hashValueStable: Int {
        var h: UInt64 = 1_469_598_103_934_665_603
        for b in utf8 {
            h ^= UInt64(b)
            h = h &* 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: h >> 1)
    }
}

extension Array {
    func shuffledStable(_ rng: inout SeededRandom) -> [Element] {
        var a = self
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() * Double(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}
