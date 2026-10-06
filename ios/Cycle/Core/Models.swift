import Foundation

// MARK: - Profile

enum CyclePhase: String, Codable, CaseIterable {
    case menstrual, follicular, ovulatory, luteal
    case lateLuteal = "late_luteal"

    var label: String { L("phase.\(rawValue)") }
}

enum Risk: String, Codable {
    case low, med, high
}

enum Focus: String, Codable, CaseIterable {
    case sleep, energy, mood, focus
    var label: String { L("focus.\(rawValue)") }
}

enum CycleStatus: String, Codable, CaseIterable {
    case natural, hormonal
    case noPeriod = "no_period"
    var label: String { L("intake.cycle.\(rawValue)") }
}

struct Intake: Codable, Equatable {
    var ageRange: String
    var cycleStatus: CycleStatus
    var changedPlans: String
    var triedChange: String
}

struct ManualCycle: Codable, Equatable {
    var lastPeriodStart: Date
    var typicalLength: Int
}

enum CycleSource: String, Codable {
    case health, manual, none
}

// MARK: - Raw inputs

/// One day of Apple Health data, already aggregated on device.
struct HealthDay {
    var sleepHours: Double?
    var sleepEfficiency: Double?
    var hrv: Double?
    var restingHR: Double?
    var steps: Double?
    var activeEnergy: Double?
    var workoutCount = 0
    var workoutMinutes = 0.0
    var wristTemp: Double?
    var flow = false
    var cycleStartMarked = false
}

struct CalendarEvent: Codable, Hashable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool

    var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

// MARK: - Daily feature row (computed on device)

struct DayFeatures: Codable, Identifiable, Hashable {
    var id: String { date }
    var date: String
    var sleepHours: Double?
    var sleepEfficiency: Double?
    var hrv: Double?
    var restingHR: Double?
    var steps: Double?
    var activeEnergy: Double?
    var workoutCount: Int
    var workoutMinutes: Double
    var wristTempDelta: Double?
    var flow: Bool
    var cycleDay: Int?
    var phase: CyclePhase?
    var eventCount: Int
    var scheduledHours: Double
    var eveningEvents: Int
    var lateEvents: Int
    var energy: Int?
}

// MARK: - Insights

struct Evidence: Codable, Hashable {
    var label: String
    var value: String
}

struct ChartPoint: Codable, Hashable {
    var x: String
    var y: Double
    var highlight: Bool?
}

struct ChartSeries: Codable, Hashable {
    var type: String
    var yLabel: String
    var points: [ChartPoint]

    enum CodingKeys: String, CodingKey {
        case type, points
        case yLabel = "y_label"
    }
}

struct ForecastDay: Codable, Hashable {
    var date: String
    var risk: Risk
    var reason: String
}

struct SuggestedExperiment: Codable, Hashable {
    var id: String
    var reason: String
}

struct Insight: Codable, Identifiable, Hashable {
    var id: String
    var weekStart: String
    var createdAt: Date
    var title: String
    var body: String
    var evidence: [Evidence]
    var chart: ChartSeries?
    var confidence: String
    var weekForecast: [ForecastDay]
    var suggestedExperiment: SuggestedExperiment?
}

// MARK: - Experiments

enum ExperimentKind: String, Codable, CaseIterable, Identifiable {
    case caffeineCutoff = "caffeine_cutoff_2pm"
    case noAlcoholWeeknights = "no_alcohol_weeknights"
    case windDown = "wind_down_30"
    case morningWalk = "morning_walk_10"
    case meetingFreeBlock = "meeting_free_block"

    var id: String { rawValue }
    var title: String { L("exp.\(rawValue).title") }
    var detail: String { L("exp.\(rawValue).detail") }
    /// Daily yes/no check-in question.
    var question: String { L("exp.\(rawValue).question") }
}

enum ExperimentStatus: String, Codable {
    case active, completed, stopped
}

struct ExperimentResult: Codable, Hashable {
    enum Verdict: String, Codable {
        case clear, unclear
        case insufficientData = "insufficient_data"
    }

    var metric: ExperimentMetric
    var before: Double?
    var beforeDays: Int
    var during: Double?
    var duringDays: Int
    var verdict: Verdict
}

enum ExperimentMetric: String, Codable {
    case sleep, hrv, energy

    var label: String { L("metric.\(rawValue)") }

    func format(_ v: Double) -> String {
        switch self {
        case .sleep: return v.hoursMinutes
        case .hrv: return L("unit.ms", Int(v.rounded()))
        case .energy: return String(format: "%.1f / 3", v)
        }
    }

    func formatDelta(_ d: Double) -> String {
        switch self {
        case .sleep: return L("unit.min", Int(abs(d * 60).rounded()))
        case .hrv: return L("unit.ms", Int(abs(d).rounded()))
        case .energy: return String(format: "%.1f", abs(d))
        }
    }
}

struct Experiment: Codable, Identifiable, Hashable {
    var id: String
    var kind: ExperimentKind
    var startDate: String
    var length: Int
    var source: String
    var checkins: [String: Bool]
    var status: ExperimentStatus
    var result: ExperimentResult?

    var start: Date { Day.date(startDate) ?? Day.today }
    var end: Date { Day.add(length - 1, to: start) }

    func dayNumber(on date: Date) -> Int { Day.between(start, date) + 1 }

    func covers(_ date: Date) -> Bool {
        let n = dayNumber(on: date)
        return n >= 1 && n <= length
    }
}

// MARK: - Settings and app state

struct AppSettings: Codable, Equatable {
    var notificationsEnabled = true
    var energyCheckEnabled = true
}

/// Everything the app keeps on device (besides cached feature rows).
struct LocalState: Codable {
    var participantCode: String?
    var participantID: String?
    var consentAt: Date?
    var enrolledAt: Date?
    var onboardingComplete = false
    var intake: Intake?
    var focus: Focus?
    var manualCycle: ManualCycle?
    var manualPeriodStarts: [String] = []
    var energy: [String: Int] = [:]
    var insights: [Insight] = []
    var insightFeedback: [String: Bool] = [:]
    var viewedInsightIDs: [String] = []
    var offeredExperimentKeys: [String] = []
    var experiments: [Experiment] = []
    var trialFlowDone = false
    var paywallChoice: String?
    var settings = AppSettings()
    var lastRefresh: Date?
    var notificationLog: [Date] = []

    init() {}

    // Tolerant decoding: new fields added in later TestFlight builds must not wipe a tester's data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        participantCode = try c.decodeIfPresent(String.self, forKey: .participantCode)
        participantID = try c.decodeIfPresent(String.self, forKey: .participantID)
        consentAt = try c.decodeIfPresent(Date.self, forKey: .consentAt)
        enrolledAt = try c.decodeIfPresent(Date.self, forKey: .enrolledAt)
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        intake = try? c.decodeIfPresent(Intake.self, forKey: .intake)
        focus = try? c.decodeIfPresent(Focus.self, forKey: .focus)
        manualCycle = try? c.decodeIfPresent(ManualCycle.self, forKey: .manualCycle)
        manualPeriodStarts = (try? c.decodeIfPresent([String].self, forKey: .manualPeriodStarts)) ?? []
        energy = (try? c.decodeIfPresent([String: Int].self, forKey: .energy)) ?? [:]
        insights = (try? c.decodeIfPresent([Insight].self, forKey: .insights)) ?? []
        insightFeedback = (try? c.decodeIfPresent([String: Bool].self, forKey: .insightFeedback)) ?? [:]
        viewedInsightIDs = (try? c.decodeIfPresent([String].self, forKey: .viewedInsightIDs)) ?? []
        offeredExperimentKeys = (try? c.decodeIfPresent([String].self, forKey: .offeredExperimentKeys)) ?? []
        experiments = (try? c.decodeIfPresent([Experiment].self, forKey: .experiments)) ?? []
        trialFlowDone = (try? c.decodeIfPresent(Bool.self, forKey: .trialFlowDone)) ?? false
        paywallChoice = try? c.decodeIfPresent(String.self, forKey: .paywallChoice)
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
        lastRefresh = try? c.decodeIfPresent(Date.self, forKey: .lastRefresh)
        notificationLog = (try? c.decodeIfPresent([Date].self, forKey: .notificationLog)) ?? []
    }

    var activeExperiment: Experiment? {
        experiments.first { $0.status == .active }
    }

    /// 1 on the day of enrolment.
    var trialDay: Int {
        guard let enrolledAt else { return 0 }
        return Day.between(enrolledAt, Date()) + 1
    }
}
