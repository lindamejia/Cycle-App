import Foundation
import Observation
import SwiftUI

enum AppTab: String, Hashable {
    case today, insights, experiment, settings
}

/// Central app state. Owns the local store, the data sources (real or demo) and every action.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var isDemo: Bool
    var state: LocalState
    private(set) var features: [DayFeatures] = []
    private(set) var upcoming: [DayFeatures] = []
    private(set) var eventsByDay: [String: [CalendarEvent]] = [:]
    private(set) var cycleSource: CycleSource = .none
    private(set) var typicalCycleLength: Int?
    private(set) var isRefreshing = false
    private(set) var isGeneratingInsight = false
    var insightError: String?
    var selectedTab: AppTab = .today
    var showTrialFlow = false

    @ObservationIgnored private var store: LocalStore
    @ObservationIgnored private var health: HealthDataSource
    @ObservationIgnored private var calendar: CalendarDataSource

    private init() {
        let demo = UserDefaults.standard.bool(forKey: "demoMode")
        let store = LocalStore(namespace: demo ? "demo" : "live")
        self.isDemo = demo
        self.store = store
        self.state = store.load(LocalState.self, "state") ?? LocalState()
        self.features = store.load([DayFeatures].self, "features") ?? []
        self.health = Self.healthSource(demo: demo)
        self.calendar = Self.calendarSource(demo: demo)
        configureAnalytics()
    }

    private static func healthSource(demo: Bool) -> HealthDataSource {
        if demo { return DemoDataSource.shared }
        return HealthKitService()
    }

    private static func calendarSource(demo: Bool) -> CalendarDataSource {
        if demo { return DemoDataSource.shared }
        return CalendarService()
    }

    // MARK: Persistence

    func save() {
        store.save(state, "state")
    }

    private func configureAnalytics() {
        Analytics.shared.enabled = !isDemo
        Analytics.shared.participantID = isDemo ? nil : state.participantID
    }

    // MARK: Demo mode

    func setDemoMode(_ on: Bool) async {
        guard on != isDemo else { return }
        UserDefaults.standard.set(on, forKey: "demoMode")
        isDemo = on
        store = LocalStore(namespace: on ? "demo" : "live")
        health = Self.healthSource(demo: on)
        calendar = Self.calendarSource(demo: on)
        state = store.load(LocalState.self, "state") ?? LocalState()
        features = store.load([DayFeatures].self, "features") ?? []
        upcoming = []
        eventsByDay = [:]
        insightError = nil
        configureAnalytics()
        if on && !state.onboardingComplete { await seedDemo() }
        selectedTab = on ? .today : selectedTab
        await onForeground(countOpen: false)
    }

    /// A ready-made tester on trial day 10 with two weeks of insights and energy check-ins.
    private func seedDemo() async {
        var s = LocalState()
        s.participantCode = "DEMO"
        s.consentAt = Date()
        s.enrolledAt = Day.add(-9, to: Day.today)
        s.onboardingComplete = true
        s.intake = Intake(ageRange: "25-34", cycleStatus: .natural, changedPlans: "several", triedChange: "couldnt_tell")
        s.focus = .energy
        for offset in 1...Config.backfillDays {
            let day = Day.add(-offset, to: Day.today)
            if let e = DemoDataSource.shared.energy(on: day) { s.energy[Day.key(day)] = e }
        }
        state = s
        save()
        await refreshData()

        let thisWeek = Day.weekStart(Date())
        let kinds: [(Int, OfflineInsightEngine.Kind)] = [(-14, .loadEnergy), (-7, .phaseHRV), (0, .sleepEnergy)]
        let seeded = kinds.map { pair in
            OfflineInsightEngine.insight(kind: pair.1, weekStart: Day.add(pair.0, to: thisWeek),
                                         features: features, upcoming: upcoming)
        }
        state.insights = Array(seeded.reversed()) // newest first
        state.insightFeedback[state.insights[2].id] = true
        state.viewedInsightIDs = state.insights.suffix(2).map(\.id)
        save()
    }

    // MARK: Lifecycle

    func onForeground(countOpen: Bool = true) async {
        guard state.onboardingComplete else { return }
        if countOpen { Analytics.shared.track(.appOpen) }
        await refreshData()
        await ensureWeeklyInsight()
        await rescheduleNotifications()
        checkTrialFlow()
        await Analytics.shared.flush()
    }

    /// Reads the last 90 days of health + calendar data (and the next 7 days of calendar)
    /// and recomputes every feature row. Fast enough to run on every open.
    func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let today = Day.today
        let from = Day.add(-(Config.backfillDays - 1), to: today)
        let healthDays = await health.healthDays(from: from, to: Day.add(1, to: today))
        let events = calendar.events(from: from, to: Day.add(8, to: today))
        var byDay: [String: [CalendarEvent]] = [:]
        for e in events { byDay[Day.key(e.start), default: []].append(e) }

        let estimator = cycleEstimator(healthDays)
        if !estimator.enabled {
            cycleSource = CycleSource.none
        } else {
            cycleSource = healthDays.values.contains(where: \.flow) ? .health : .manual
        }
        typicalCycleLength = estimator.enabled ? estimator.typicalLength : nil

        let past = (0..<Config.backfillDays).reversed().map { Day.add(-$0, to: today) }
        let next = (1...7).map { Day.add($0, to: today) }
        eventsByDay = byDay
        features = FeatureBuilder.build(days: past, health: healthDays, eventsByDay: byDay,
                                        energy: state.energy, cycle: estimator)
        upcoming = FeatureBuilder.build(days: next, health: [:], eventsByDay: byDay,
                                        energy: [:], cycle: estimator)
        store.save(features, "features")
        state.lastRefresh = Date()
        finishExperimentsIfDue()
        save()
    }

    private func cycleEstimator(_ healthDays: [String: HealthDay]) -> CycleEstimator {
        let flowDays = healthDays.filter { $0.value.flow }.compactMap { Day.date($0.key) }
        let marked = healthDays.filter { $0.value.cycleStartMarked }.compactMap { Day.date($0.key) }
        let manual = state.manualPeriodStarts.compactMap(Day.date)
        if isDemo {
            // Demo flow days come from the generator, so the estimate matches its cycle.
            return CycleEstimator.make(flowDays: flowDays, markedStarts: [], manualStarts: [],
                                       manual: nil, status: .natural)
        }
        return CycleEstimator.make(flowDays: flowDays, markedStarts: marked, manualStarts: manual,
                                   manual: state.manualCycle, status: state.intake?.cycleStatus)
    }

    var todayFeatures: DayFeatures? { features.last }

    var todayForecast: DayForecast? {
        guard let f = todayFeatures else { return nil }
        return ForecastEngine.forecast(for: f, baselines: Baselines(features: features))
    }

    // MARK: Onboarding

    /// Pseudonymous enrolment: anonymous Supabase user + invite code.
    func redeemInvite(_ code: String) async throws {
        let consentAt = state.consentAt ?? Date()
        let data = try await SupabaseClient.shared.rpc("redeem_invite", params: [
            "p_code": code,
            "p_locale": AppLanguage.code,
            "p_app_version": Config.appVersion,
            "p_consent_version": Config.consentVersion,
            "p_consent_at": ISO8601DateFormatter().string(from: consentAt),
        ])
        struct Row: Decodable {
            let participant_id: String
            let invite_code: String
        }
        guard let row = try? JSONDecoder().decode([Row].self, from: data).first else { throw BackendError.decoding }
        state.participantID = row.participant_id
        state.participantCode = row.invite_code
        save()
        configureAnalytics()
    }

    func requestHealthAndCalendar() async {
        try? await health.requestAuthorization()
        _ = await calendar.requestAccess()
    }

    /// True when Apple Health has period data, so onboarding can skip the manual cycle questions.
    func hasHealthFlowData() async -> Bool {
        let from = Day.add(-Config.backfillDays, to: Day.today)
        let days = await health.healthDays(from: from, to: Day.add(1, to: Day.today))
        return days.values.contains(where: \.flow)
    }

    func completeOnboarding(intake: Intake, focus: Focus, manualCycle: ManualCycle?) async {
        state.intake = intake
        state.focus = focus
        state.manualCycle = manualCycle
        state.enrolledAt = state.enrolledAt ?? Date()
        save()

        Analytics.shared.answer(survey: "intake", question: "age_range", answer: intake.ageRange)
        Analytics.shared.answer(survey: "intake", question: "cycle_status", answer: intake.cycleStatus.rawValue)
        Analytics.shared.answer(survey: "intake", question: "changed_plans", answer: intake.changedPlans)
        Analytics.shared.answer(survey: "intake", question: "tried_change", answer: intake.triedChange)
        Analytics.shared.answer(survey: "intake", question: "focus", answer: focus.rawValue)
        Analytics.shared.track(.appOpen)

        await refreshData() // the 90-day backfill
        state.onboardingComplete = true
        save()
        Task {
            await ensureWeeklyInsight()
            await rescheduleNotifications()
            await Analytics.shared.flush()
        }
    }

    // MARK: Manual inputs

    func recordEnergy(_ level: Int, date: Date = Date(), source: String) {
        let key = Day.key(date)
        state.energy[key] = level
        if let i = features.firstIndex(where: { $0.date == key }) { features[i].energy = level }
        save()
        Analytics.shared.track(.energyCheckin, ["level": String(level), "source": source])
    }

    func periodStartedToday() {
        let key = Day.key(Date())
        if !state.manualPeriodStarts.contains(key) { state.manualPeriodStarts.append(key) }
        save()
        Task { await refreshData() }
    }

    // MARK: Insights

    /// The insight week flips on Monday at 08:00 local time.
    private var currentInsightWeek: String {
        Day.key(Day.weekStart(Date().addingTimeInterval(-8 * 3600)))
    }

    func ensureWeeklyInsight(force: Bool = false) async {
        guard state.onboardingComplete, !isGeneratingInsight else { return }
        let week = currentInsightWeek
        if !force, state.insights.contains(where: { $0.weekStart >= week }) { return }
        // The very first insight is written on day 1, whatever the weekday.
        let weekStart = state.insights.isEmpty ? Day.key(Day.weekStart(Date())) : week

        isGeneratingInsight = true
        insightError = nil
        defer { isGeneratingInsight = false }

        do {
            let insight: Insight
            if isDemo {
                insight = OfflineInsightEngine.insight(kind: .sleepEnergy, weekStart: Day.date(weekStart) ?? Day.today,
                                                       features: features, upcoming: upcoming)
            } else {
                let summary = SummaryBuilder.build(weekStart: weekStart, state: state, features: features,
                                                   upcoming: upcoming, eventsByDay: eventsByDay,
                                                   typicalCycleLength: typicalCycleLength)
                insight = try await InsightService.generate(summary)
            }
            state.insights.removeAll { $0.id == insight.id }
            state.insights.insert(insight, at: 0)
            save()
            await rescheduleNotifications()
        } catch {
            if case BackendError.notConfigured = error {
                insightError = L("error.notConfigured")
            } else {
                insightError = L("insights.error")
            }
        }
    }

    func markViewed(_ insight: Insight) {
        guard !state.viewedInsightIDs.contains(insight.id) else { return }
        state.viewedInsightIDs.append(insight.id)
        save()
        Analytics.shared.track(.insightViewed, ["insight_id": insight.id, "week_start": insight.weekStart])
    }

    func setFeedback(_ insight: Insight, useful: Bool) {
        state.insightFeedback[insight.id] = useful
        save()
        Analytics.shared.track(.insightFeedback, ["insight_id": insight.id, "value": useful ? "useful" : "not_useful"])
    }

    /// The next 7 days from the latest insight (falls back to the on-device forecast).
    var weekForecast: [ForecastDay] {
        let todayKey = Day.key(Date())
        if let latest = state.insights.first {
            let future = latest.weekForecast.filter { $0.date > todayKey }
            if !future.isEmpty { return future }
        }
        let b = Baselines(features: features)
        return upcoming.map { f in
            let fc = ForecastEngine.forecast(for: f, baselines: b, includeBody: false)
            return ForecastDay(date: f.date, risk: fc.risk, reason: fc.reasons.joined(separator: ", "))
        }
    }

    // MARK: Experiments

    var experimentsUnlocked: Bool { state.trialDay >= Config.experimentUnlockDay }

    /// The experiment suggested by the latest insight, if it is a known one.
    var suggestedExperiment: (kind: ExperimentKind, reason: String, insightID: String)? {
        for insight in state.insights {
            if let s = insight.suggestedExperiment, let kind = ExperimentKind(rawValue: s.id) {
                return (kind, s.reason, insight.id)
            }
        }
        return nil
    }

    func markExperimentOffered(_ kind: ExperimentKind, insightID: String) {
        let key = insightID + "|" + kind.rawValue
        guard !state.offeredExperimentKeys.contains(key) else { return }
        state.offeredExperimentKeys.append(key)
        save()
        Analytics.shared.track(.experimentOffered, ["experiment": kind.rawValue, "insight_id": insightID])
    }

    func startExperiment(_ kind: ExperimentKind, source: String) async {
        guard state.activeExperiment == nil else { return }
        let e = Experiment(id: UUID().uuidString, kind: kind, startDate: Day.key(Date()),
                           length: Config.experimentLengthDays, source: source, checkins: [:],
                           status: .active, result: nil)
        state.experiments.append(e)
        save()
        Analytics.shared.track(.experimentStarted, ["experiment": kind.rawValue, "source": source])
        await rescheduleNotifications()
    }

    func checkIn(experimentID: String, date: Date = Date(), did: Bool, source: String) {
        guard let i = state.experiments.firstIndex(where: { $0.id == experimentID }),
              state.experiments[i].covers(date) else { return }
        let key = Day.key(date)
        state.experiments[i].checkins[key] = did
        save()
        Analytics.shared.track(.experimentCheckin, [
            "experiment": state.experiments[i].kind.rawValue,
            "day": String(state.experiments[i].dayNumber(on: date)),
            "value": did ? "yes" : "no",
            "source": source,
        ])
    }

    func stopExperiment() async {
        guard let i = state.experiments.firstIndex(where: { $0.status == .active }) else { return }
        state.experiments[i].status = .stopped
        state.experiments[i].result = ExperimentEngine.evaluate(state.experiments[i], features: features)
        save()
        await rescheduleNotifications()
    }

    private func finishExperimentsIfDue() {
        for i in state.experiments.indices where state.experiments[i].status == .active {
            let e = state.experiments[i]
            guard Day.today > e.end else { continue }
            state.experiments[i].status = .completed
            let result = ExperimentEngine.evaluate(e, features: features)
            state.experiments[i].result = result
            Analytics.shared.track(.experimentCompleted, [
                "experiment": e.kind.rawValue,
                "yes_days": String(e.checkins.values.filter { $0 }.count),
                "verdict": result.verdict.rawValue,
            ])
        }
    }

    // MARK: Notifications

    func rescheduleNotifications() async {
        state.notificationLog = await NotificationScheduler.reschedule(state: state, highRiskDays: weekForecast)
        save()
    }

    func setNotifications(enabled: Bool) async {
        state.settings.notificationsEnabled = enabled
        save()
        if enabled { await NotificationScheduler.requestPermission() }
        await rescheduleNotifications()
    }

    func setEnergyCheck(enabled: Bool) async {
        state.settings.energyCheckEnabled = enabled
        save()
        await rescheduleNotifications()
    }

    // MARK: Day 21

    func checkTrialFlow() {
        if state.onboardingComplete, !state.trialFlowDone, state.trialDay >= Config.trialLengthDays {
            showTrialFlow = true
        }
    }

    func previewTrialFlow() {
        showTrialFlow = true
    }

    func submitTrialSurvey(mostUseful: String, disappointment: String, worthPaying: String) {
        Analytics.shared.answer(survey: "day21", question: "most_useful_insight", answer: mostUseful)
        Analytics.shared.answer(survey: "day21", question: "disappointment", answer: disappointment)
        let text = worthPaying.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Analytics.shared.answer(survey: "day21", question: "worth_paying_for", answer: text, freeText: true)
        }
    }

    func paywallShown() { Analytics.shared.track(.paywallShown) }

    func paywallChoice(subscribe: Bool) {
        state.paywallChoice = subscribe ? "subscribe" : "not_now"
        save()
        Analytics.shared.track(subscribe ? .paywallSubscribeTap : .paywallDismiss)
    }

    func finishTrialFlow() {
        state.trialFlowDone = true
        showTrialFlow = false
        save()
        Task { await Analytics.shared.flush() }
    }

    // MARK: Export and delete

    func exportData() -> URL? {
        struct Export: Encodable {
            let exportedAt: Date
            let participantCode: String?
            let consentAt: Date?
            let enrolledAt: Date?
            let intake: Intake?
            let focus: Focus?
            let manualCycle: ManualCycle?
            let manualPeriodStarts: [String]
            let energyCheckins: [String: Int]
            let insights: [Insight]
            let insightFeedback: [String: Bool]
            let experiments: [Experiment]
            let dailyFeatures: [DayFeatures]
        }
        let export = Export(exportedAt: Date(), participantCode: state.participantCode, consentAt: state.consentAt,
                            enrolledAt: state.enrolledAt, intake: state.intake, focus: state.focus,
                            manualCycle: state.manualCycle, manualPeriodStarts: state.manualPeriodStarts,
                            energyCheckins: state.energy, insights: state.insights,
                            insightFeedback: state.insightFeedback, experiments: state.experiments,
                            dailyFeatures: features)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(export) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cycle-export-\(Day.key(Date())).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Deletes the participant's server rows (events, survey answers, insights, the anonymous
    /// account) and every local file, then returns to onboarding.
    func deleteAllData(localOnly: Bool = false) async throws {
        let live = LocalStore(namespace: "live")
        let liveState = live.load(LocalState.self, "state")
        if !localOnly, Config.isBackendConfigured, liveState?.participantID != nil {
            // Server side, delete_my_data() records the deletion anonymously in deletion_log
            // (a data_deleted event would be erased together with the participant's rows).
            _ = try await SupabaseClient.shared.rpc("delete_my_data")
        }
        live.wipe()
        LocalStore(namespace: "demo").wipe()
        Analytics.shared.clear()
        await SupabaseClient.shared.signOut()
        NotificationScheduler.cancelAll()
        UserDefaults.standard.removeObject(forKey: "demoMode")

        isDemo = false
        store = live
        health = HealthKitService()
        calendar = CalendarService()
        state = LocalState()
        features = []
        upcoming = []
        eventsByDay = [:]
        insightError = nil
        selectedTab = .today
        configureAnalytics()
    }
}
