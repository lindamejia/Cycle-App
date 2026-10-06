import Foundation

/// The weekly summary sent to the insight engine. Contains daily numbers, dates, cycle
/// estimates and event titles only: no names, no raw timestamps beyond dates.
struct WeeklySummary: Encodable {
    struct Profile: Encodable {
        var ageRange: String?
        var cycleStatus: String?
        var focus: String?
        var typicalCycleLength: Int?
    }

    struct EventRef: Encodable {
        var t: Int
        var part: String
        var min: Int
    }

    struct Row: Encodable {
        var date: String
        var sleepH: Double?
        var sleepEff: Double?
        var hrv: Double?
        var rhr: Double?
        var steps: Int?
        var activeKcal: Int?
        var workouts: Int?
        var workoutMin: Int?
        var tempDelta: Double?
        var flow: Bool?
        var cycleDay: Int?
        var phase: String?
        var events: Int
        var scheduledH: Double
        var eveningEvents: Int
        var lateEvents: Int
        var energy: Int?
        var ev: [EventRef]
    }

    struct Group: Encodable {
        var n: Int
        var sleepH: Double?
        var hrv: Double?
        var rhr: Double?
        var energy: Double?
        var energyN: Int
    }

    struct Stats: Encodable {
        var byPhase: [String: Group]
        var nightsUnder6h30: Group
        var nightsOver6h30: Group
        var busyDays4PlusEvents: Group
        var lighterDays: Group
        var daysWithLateEvents: Group
        var energyCheckins: Int
    }

    struct PreviousInsight: Encodable {
        var weekStart: String
        var title: String
        var feedback: String?
    }

    struct ActiveExperiment: Encodable {
        var id: String
        var day: Int
        var length: Int
        var yes: Int
        var no: Int
    }

    var weekStart: String
    var today: String
    var locale: String
    var profile: Profile
    var days: [Row]
    var upcoming: [Row]
    var titles: [String: String]
    var stats: Stats
    var previousInsights: [PreviousInsight]
    var activeExperiment: ActiveExperiment?

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return try e.encode(self)
    }
}

enum SummaryBuilder {
    static func build(weekStart: String, state: LocalState, features: [DayFeatures], upcoming: [DayFeatures],
                      eventsByDay: [String: [CalendarEvent]], typicalCycleLength: Int?) -> WeeklySummary {
        var titleIDs: [String: Int] = [:]
        var titles: [String: String] = [:]
        func refs(_ date: String) -> [WeeklySummary.EventRef] {
            (eventsByDay[date] ?? []).sorted { $0.start < $1.start }.map { e in
                let title = String(e.title.prefix(80))
                let id: Int
                if let existing = titleIDs[title] {
                    id = existing
                } else {
                    id = titleIDs.count + 1
                    titleIDs[title] = id
                    titles[String(id)] = title
                }
                return .init(t: id, part: FeatureBuilder.partOfDay(e), min: Int(e.durationMinutes.rounded()))
            }
        }

        let window = Array(features.suffix(Config.summaryDays))
        let rows = window.map { f in row(f, refs: refs(f.date)) }
        let next = upcoming.map { f in row(f, refs: refs(f.date)) }

        let previous = state.insights.prefix(8).map { i in
            WeeklySummary.PreviousInsight(
                weekStart: i.weekStart, title: i.title,
                feedback: state.insightFeedback[i.id].map { $0 ? "useful" : "not_useful" })
        }

        var active: WeeklySummary.ActiveExperiment?
        if let e = state.activeExperiment {
            active = .init(id: e.kind.rawValue, day: e.dayNumber(on: Date()), length: e.length,
                           yes: e.checkins.values.filter { $0 }.count,
                           no: e.checkins.values.filter { !$0 }.count)
        }

        return WeeklySummary(
            weekStart: weekStart,
            today: Day.key(Date()),
            locale: AppLanguage.code,
            profile: .init(ageRange: state.intake?.ageRange,
                           cycleStatus: state.intake?.cycleStatus.rawValue,
                           focus: state.focus?.rawValue,
                           typicalCycleLength: typicalCycleLength),
            days: rows,
            upcoming: next,
            titles: titles,
            stats: stats(window),
            previousInsights: Array(previous),
            activeExperiment: active)
    }

    private static func row(_ f: DayFeatures, refs: [WeeklySummary.EventRef]) -> WeeklySummary.Row {
        WeeklySummary.Row(
            date: f.date,
            sleepH: f.sleepHours.map { round($0, 2) },
            sleepEff: f.sleepEfficiency.map { round($0, 2) },
            hrv: f.hrv.map { round($0, 0) },
            rhr: f.restingHR.map { round($0, 0) },
            steps: f.steps.map { Int($0.rounded()) },
            activeKcal: f.activeEnergy.map { Int($0.rounded()) },
            workouts: f.workoutCount > 0 ? f.workoutCount : nil,
            workoutMin: f.workoutCount > 0 ? Int(f.workoutMinutes.rounded()) : nil,
            tempDelta: f.wristTempDelta.map { round($0, 2) },
            flow: f.flow ? true : nil,
            cycleDay: f.cycleDay,
            phase: f.phase?.rawValue,
            events: f.eventCount,
            scheduledH: round(f.scheduledHours, 1),
            eveningEvents: f.eveningEvents,
            lateEvents: f.lateEvents,
            energy: f.energy,
            ev: refs)
    }

    static func stats(_ rows: [DayFeatures]) -> WeeklySummary.Stats {
        var byPhase: [String: WeeklySummary.Group] = [:]
        for phase in CyclePhase.allCases {
            let g = rows.filter { $0.phase == phase }
            if !g.isEmpty { byPhase[phase.rawValue] = group(g) }
        }
        return WeeklySummary.Stats(
            byPhase: byPhase,
            nightsUnder6h30: group(rows.filter { ($0.sleepHours ?? 99) < 6.5 }),
            nightsOver6h30: group(rows.filter { ($0.sleepHours ?? 0) >= 6.5 }),
            busyDays4PlusEvents: group(rows.filter { $0.eventCount >= 4 }),
            lighterDays: group(rows.filter { $0.eventCount < 4 }),
            daysWithLateEvents: group(rows.filter { $0.lateEvents > 0 }),
            energyCheckins: rows.compactMap(\.energy).count)
    }

    static func group(_ rows: [DayFeatures]) -> WeeklySummary.Group {
        let energy = rows.compactMap { $0.energy.map(Double.init) }
        return WeeklySummary.Group(
            n: rows.count,
            sleepH: mean(rows.compactMap(\.sleepHours)).map { round($0, 2) },
            hrv: mean(rows.compactMap(\.hrv)).map { round($0, 1) },
            rhr: mean(rows.compactMap(\.restingHR)).map { round($0, 1) },
            energy: mean(energy).map { round($0, 2) },
            energyN: energy.count)
    }

    static func round(_ v: Double, _ places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (v * p).rounded() / p
    }
}
