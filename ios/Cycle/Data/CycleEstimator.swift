import Foundation

/// Estimates cycle day and phase from period starts (Apple Health flow, the
/// "My period started" button, or the onboarding answers).
struct CycleEstimator {
    let periodStarts: [Date]
    let typicalLength: Int
    let enabled: Bool

    static let disabled = CycleEstimator(periodStarts: [], typicalLength: 28, enabled: false)

    static func make(flowDays: [Date], markedStarts: [Date], manualStarts: [Date],
                     manual: ManualCycle?, status: CycleStatus?) -> CycleEstimator {
        guard status == nil || status == .natural else { return .disabled }

        // A flow day with no flow in the 3 days before it starts a period.
        var starts: [Date] = markedStarts + manualStarts
        let flow = Array(Set(flowDays.map(Day.start))).sorted()
        var previous: Date?
        for d in flow {
            if let p = previous, Day.between(p, d) <= 3 {
                previous = d
                continue
            }
            starts.append(d)
            previous = d
        }
        if let m = manual { starts.append(Day.start(m.lastPeriodStart)) }

        // Merge starts closer than 10 days (same period recorded twice).
        var merged: [Date] = []
        for s in Array(Set(starts.map(Day.start))).sorted() {
            if let last = merged.last, Day.between(last, s) < 10 { continue }
            merged.append(s)
        }

        let gaps = zip(merged, merged.dropFirst())
            .map { Double(Day.between($0, $1)) }
            .filter { $0 >= 21 && $0 <= 40 }
        let length = median(gaps).map { Int($0.rounded()) } ?? manual?.typicalLength ?? 28
        return CycleEstimator(periodStarts: merged, typicalLength: length, enabled: !merged.isEmpty)
    }

    func info(for date: Date) -> (day: Int, phase: CyclePhase)? {
        guard enabled, let first = periodStarts.first else { return nil }
        let d = Day.start(date)
        let L = typicalLength
        let day: Int
        if let last = periodStarts.last(where: { $0 <= d }) {
            let diff = Day.between(last, d)
            day = diff < L + 7 ? diff + 1 : diff % L + 1 // project forward after a long gap
        } else {
            let diff = Day.between(first, d) // negative: project backwards
            day = ((diff % L) + L) % L + 1
        }
        return (day, Self.phase(day: day, length: L))
    }

    static func phase(day: Int, length: Int) -> CyclePhase {
        let ovulation = max(length - 14, 8)
        if day <= 5 { return .menstrual }
        if abs(day - ovulation) <= 1 { return .ovulatory }
        if day < ovulation { return .follicular }
        if day >= length - 4 { return .lateLuteal }
        return .luteal
    }
}
