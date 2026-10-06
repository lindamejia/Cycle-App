import Foundation
import UserNotifications

/// Local notifications, at most `Config.notificationWeeklyCap` per week (Monday to Sunday).
/// No streaks, no reminders about missed days.
///
/// When more candidates exist than the cap allows, they are kept in this order:
/// Monday insight, day-before heads-up (high-risk days), experiment check-in, energy tap.
enum NotificationScheduler {
    enum Kind: String {
        case weeklyInsight = "weekly_insight"
        case headsUp = "heads_up"
        case experiment
        case energy

        var priority: Int {
            switch self {
            case .weeklyInsight: return 0
            case .headsUp: return 1
            case .experiment: return 2
            case .energy: return 3
            }
        }
    }

    enum Category {
        static let energy = "ENERGY"
        static let experiment = "EXPERIMENT"
        static let plain = "PLAIN"
    }

    enum Action {
        static let energyLow = "ENERGY_1"
        static let energyOkay = "ENERGY_2"
        static let energyGood = "ENERGY_3"
        static let experimentYes = "EXP_YES"
        static let experimentNo = "EXP_NO"
    }

    static let horizonDays = 14

    static func registerCategories() {
        let energy = UNNotificationCategory(
            identifier: Category.energy,
            actions: [
                UNNotificationAction(identifier: Action.energyLow, title: L("energy.low"), options: []),
                UNNotificationAction(identifier: Action.energyOkay, title: L("energy.okay"), options: []),
                UNNotificationAction(identifier: Action.energyGood, title: L("energy.good"), options: []),
            ],
            intentIdentifiers: [])
        let experiment = UNNotificationCategory(
            identifier: Category.experiment,
            actions: [
                UNNotificationAction(identifier: Action.experimentYes, title: L("common.yes"), options: []),
                UNNotificationAction(identifier: Action.experimentNo, title: L("common.no"), options: []),
            ],
            intentIdentifiers: [])
        let plain = UNNotificationCategory(identifier: Category.plain, actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([energy, experiment, plain])
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private struct Candidate {
        var date: Date
        var kind: Kind
        var title: String
        var body: String
        var category: String
        var info: [String: String] = [:]
    }

    /// Clears pending notifications and schedules the next two weeks. Returns the updated log
    /// of fire dates (past ones kept so the weekly cap counts what was already delivered).
    static func reschedule(state: LocalState, highRiskDays: [ForecastDay]) async -> [Date] {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let pastLog = state.notificationLog.filter { $0 <= now && $0 > Day.add(-horizonDays, to: now) }
        let settings = await center.notificationSettings()
        guard state.onboardingComplete, state.settings.notificationsEnabled,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return pastLog }

        var candidates: [Candidate] = []
        let today = Day.today
        for offset in 0..<horizonDays {
            let day = Day.add(offset, to: today)
            let key = Day.key(day)
            if Day.isoWeekday(day) == 1 {
                candidates.append(Candidate(date: Day.at(8, on: day), kind: .weeklyInsight,
                                            title: L("notif.weekly.title"), body: L("notif.weekly.body"),
                                            category: Category.plain))
            }
            if let e = state.activeExperiment, e.covers(day), e.checkins[key] == nil {
                candidates.append(Candidate(date: Day.at(20, 30, on: day), kind: .experiment,
                                            title: e.kind.title, body: e.kind.question,
                                            category: Category.experiment,
                                            info: ["experiment_id": e.id, "date": key]))
            } else if state.settings.energyCheckEnabled, state.energy[key] == nil {
                candidates.append(Candidate(date: Day.at(20, 30, on: day), kind: .energy,
                                            title: L("notif.energy.title"), body: L("notif.energy.body"),
                                            category: Category.energy, info: ["date": key]))
            }
        }
        for f in highRiskDays where f.risk == .high {
            guard let day = Day.date(f.date) else { continue }
            candidates.append(Candidate(date: Day.at(19, on: Day.add(-1, to: day)), kind: .headsUp,
                                        title: L("notif.headsup.title"),
                                        body: L("notif.headsup.body", f.reason),
                                        category: Category.plain))
        }
        candidates = candidates.filter { $0.date > now.addingTimeInterval(60) }

        // Apply the weekly cap. Energy taps are spread across the week (Tue, Thu, Sun first).
        let energyPreference = [2: 0, 4: 1, 7: 2, 3: 3, 6: 4, 5: 5, 1: 6]
        var chosen: [Candidate] = []
        let byWeek = Dictionary(grouping: candidates) { Day.key(Day.weekStart($0.date)) }
        for (weekKey, items) in byWeek {
            let used = pastLog.filter { Day.key(Day.weekStart($0)) == weekKey }.count
            let allowed = max(0, Config.notificationWeeklyCap - used)
            let ranked = items.sorted {
                if $0.kind.priority != $1.kind.priority { return $0.kind.priority < $1.kind.priority }
                if $0.kind == .energy {
                    return energyPreference[Day.isoWeekday($0.date), default: 9] < energyPreference[Day.isoWeekday($1.date), default: 9]
                }
                return $0.date < $1.date
            }
            chosen += ranked.prefix(allowed)
        }

        for c in chosen {
            let content = UNMutableNotificationContent()
            content.title = c.title
            content.body = c.body
            content.categoryIdentifier = c.category
            content.sound = nil
            var info = c.info
            info["kind"] = c.kind.rawValue
            content.userInfo = info
            let comps = Day.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: c.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "\(c.kind.rawValue)-\(Day.key(c.date))"
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        return pastLog + chosen.map(\.date)
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
