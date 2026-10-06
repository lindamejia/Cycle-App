import Foundation

/// Honest before/after comparison for a finished experiment.
///
/// Before: the 14 days before the experiment started.
/// During: the days she answered "yes". Sleep and HRV are read from the following
/// morning's row (sleep is filed under the day it ends), energy from the same day.
enum ExperimentEngine {
    static let baselineDays = 14
    static let minimumDays = 4

    static func evaluate(_ e: Experiment, features: [DayFeatures]) -> ExperimentResult {
        let rows = Dictionary(features.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let yesDays = e.checkins.filter { $0.value }.compactMap { Day.date($0.key) }.filter { e.covers($0) }
        let baseline = (1...baselineDays).map { Day.add(-$0, to: e.start) }

        let candidates: [ExperimentMetric]
        switch e.kind {
        case .caffeineCutoff, .windDown: candidates = [.sleep]
        case .noAlcoholWeeknights: candidates = [.hrv, .sleep]
        case .morningWalk, .meetingFreeBlock: candidates = [.energy, .hrv]
        }

        var fallback: ExperimentResult?
        for metric in candidates {
            let before = values(metric, days: baseline, rows: rows)
            let during = values(metric, days: yesDays, rows: rows)
            let result = compare(metric, before: before, during: during)
            if result.verdict != .insufficientData { return result }
            if fallback == nil { fallback = result }
        }
        return fallback ?? ExperimentResult(metric: candidates[0], before: nil, beforeDays: 0,
                                            during: nil, duringDays: 0, verdict: .insufficientData)
    }

    private static func values(_ metric: ExperimentMetric, days: [Date], rows: [String: DayFeatures]) -> [Double] {
        days.compactMap { d in
            switch metric {
            case .sleep: return rows[Day.key(Day.add(1, to: d))]?.sleepHours
            case .hrv: return rows[Day.key(Day.add(1, to: d))]?.hrv
            case .energy: return rows[Day.key(d)]?.energy.map(Double.init)
            }
        }
    }

    private static func compare(_ metric: ExperimentMetric, before: [Double], during: [Double]) -> ExperimentResult {
        let b = mean(before)
        let d = mean(during)
        var verdict = ExperimentResult.Verdict.insufficientData
        if before.count >= minimumDays, during.count >= minimumDays, let b, let d {
            let minimal: Double
            switch metric {
            case .sleep: minimal = 0.25
            case .hrv: minimal = 3
            case .energy: minimal = 0.3
            }
            let threshold = max(minimal, 0.5 * (standardDeviation(before) ?? 0))
            verdict = abs(d - b) >= threshold ? .clear : .unclear
        }
        return ExperimentResult(metric: metric, before: b, beforeDays: before.count,
                                during: d, duringDays: during.count, verdict: verdict)
    }
}
