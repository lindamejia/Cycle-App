import Foundation

/// Demo-mode insights written on device from the demo data, so the app works in the
/// simulator without a backend. Real testers always get insights from the Edge Function.
enum OfflineInsightEngine {
    enum Kind: CaseIterable { case sleepEnergy, phaseHRV, loadEnergy }

    static func insight(kind: Kind, weekStart: Date, features: [DayFeatures], upcoming: [DayFeatures]) -> Insight {
        let end = Day.add(1, to: weekStart) // data up to the Monday the insight was written
        let window = features.filter { (Day.date($0.date) ?? .distantFuture) < end }.suffix(28)
        let rows = Array(window)
        let baselines = Baselines(features: rows)

        var insight: Insight
        switch kind {
        case .sleepEnergy: insight = sleepEnergy(rows)
        case .phaseHRV: insight = phaseHRV(rows)
        case .loadEnergy: insight = loadEnergy(rows)
        }
        insight.weekStart = Day.key(weekStart)
        insight.createdAt = Day.at(8, on: weekStart)
        insight.weekForecast = upcoming.map { f in
            let fc = ForecastEngine.forecast(for: f, baselines: baselines, includeBody: false)
            return ForecastDay(date: f.date, risk: fc.risk, reason: fc.reasons.joined(separator: ", "))
        }
        return insight
    }

    private static func blank(_ id: String) -> Insight {
        Insight(id: "demo-" + id, weekStart: "", createdAt: Date(), title: "", body: "", evidence: [],
                chart: nil, confidence: "medium", weekForecast: [], suggestedExperiment: nil)
    }

    private static func dayLabel(_ key: String) -> String {
        Day.date(key).map { Day.display($0, "EEEd") } ?? key
    }

    private static func sleepEnergy(_ rows: [DayFeatures]) -> Insight {
        let checked = rows.filter { $0.energy != nil }
        let low = checked.filter { $0.energy == 1 }
        let lowAfterShort = low.filter { ($0.sleepHours ?? 99) < 6.5 }.count
        let short = rows.filter { ($0.sleepHours ?? 99) < 6.5 }.count
        let lowLateLuteal = low.filter { $0.phase == .lateLuteal || $0.phase == .luteal }.count

        var i = blank("sleep-energy-" + (rows.last?.date ?? ""))
        i.title = L("demo.sleep.title")
        i.body = L("demo.sleep.body", low.count, lowAfterShort, lowLateLuteal)
        i.evidence = [
            Evidence(label: L("demo.ev.lowDays"), value: L("demo.ev.ofCheckins", low.count, checked.count)),
            Evidence(label: L("demo.ev.afterShort"), value: L("demo.ev.of", lowAfterShort, low.count)),
            Evidence(label: L("demo.ev.shortNights"), value: L("demo.ev.of", short, rows.count)),
        ]
        let last = rows.suffix(14)
        i.chart = ChartSeries(type: "bar", yLabel: L("metric.sleep.hours"), points: last.map {
            ChartPoint(x: dayLabel($0.date), y: SummaryBuilder.round($0.sleepHours ?? 0, 1), highlight: $0.energy == 1)
        })
        i.confidence = low.count >= 3 && lowAfterShort * 2 >= low.count ? "medium" : "low"
        i.suggestedExperiment = SuggestedExperiment(id: ExperimentKind.windDown.rawValue, reason: L("demo.sleep.exp"))
        return i
    }

    private static func phaseHRV(_ rows: [DayFeatures]) -> Insight {
        let follicular = rows.filter { $0.phase == .follicular }.compactMap(\.hrv)
        let late = rows.filter { $0.phase == .lateLuteal }.compactMap(\.hrv)
        let f = mean(follicular) ?? 0
        let l = mean(late) ?? 0

        var i = blank("phase-hrv-" + (rows.last?.date ?? ""))
        i.title = L("demo.phase.title")
        i.body = L("demo.phase.body", Int(f.rounded()), Int(l.rounded()))
        i.evidence = [
            Evidence(label: L("demo.ev.follicularHRV"), value: L("unit.ms", Int(f.rounded()))),
            Evidence(label: L("demo.ev.lateLutealHRV"), value: L("unit.ms", Int(l.rounded()))),
            Evidence(label: L("demo.ev.days"), value: "\(follicular.count) / \(late.count)"),
        ]
        i.chart = ChartSeries(type: "line", yLabel: L("metric.hrv.ms"), points: rows.map {
            ChartPoint(x: dayLabel($0.date), y: SummaryBuilder.round($0.hrv ?? 0, 0), highlight: $0.phase == .lateLuteal)
        })
        i.confidence = follicular.count >= 4 && late.count >= 3 ? "medium" : "low"
        i.suggestedExperiment = SuggestedExperiment(id: ExperimentKind.caffeineCutoff.rawValue, reason: L("demo.phase.exp"))
        return i
    }

    private static func loadEnergy(_ rows: [DayFeatures]) -> Insight {
        let busy = rows.filter { $0.eventCount >= 4 }.compactMap { $0.energy.map(Double.init) }
        let light = rows.filter { $0.eventCount < 4 }.compactMap { $0.energy.map(Double.init) }
        let b = mean(busy) ?? 0
        let l = mean(light) ?? 0

        var i = blank("load-energy-" + (rows.last?.date ?? ""))
        i.title = L("demo.load.title")
        i.body = L("demo.load.body", b, busy.count, l, light.count)
        i.evidence = [
            Evidence(label: L("demo.ev.busyEnergy"), value: String(format: "%.1f / 3", b)),
            Evidence(label: L("demo.ev.lightEnergy"), value: String(format: "%.1f / 3", l)),
        ]
        i.chart = ChartSeries(type: "bar", yLabel: L("metric.events"), points: rows.suffix(14).map {
            ChartPoint(x: dayLabel($0.date), y: Double($0.eventCount), highlight: $0.energy == 1)
        })
        i.confidence = abs(b - l) >= 0.3 && busy.count >= 4 ? "medium" : "low"
        i.suggestedExperiment = SuggestedExperiment(id: ExperimentKind.meetingFreeBlock.rawValue, reason: L("demo.load.exp"))
        return i
    }
}
