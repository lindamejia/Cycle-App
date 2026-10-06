import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    // Show banners while the app is open too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // Taps and action buttons (energy Low / Okay / Good, experiment Yes / No).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? "unknown"
        let date = (info["date"] as? String).flatMap(Day.date) ?? Date()
        let action = response.actionIdentifier

        Task { @MainActor in
            let model = AppModel.shared
            switch action {
            case NotificationScheduler.Action.energyLow:
                model.recordEnergy(1, date: date, source: "notification")
            case NotificationScheduler.Action.energyOkay:
                model.recordEnergy(2, date: date, source: "notification")
            case NotificationScheduler.Action.energyGood:
                model.recordEnergy(3, date: date, source: "notification")
            case NotificationScheduler.Action.experimentYes, NotificationScheduler.Action.experimentNo:
                if let id = info["experiment_id"] as? String {
                    model.checkIn(experimentID: id, date: date,
                                  did: action == NotificationScheduler.Action.experimentYes, source: "notification")
                }
            case UNNotificationDefaultActionIdentifier:
                Analytics.shared.track(.notificationOpened, ["type": kind])
                switch kind {
                case NotificationScheduler.Kind.weeklyInsight.rawValue: model.selectedTab = .insights
                case NotificationScheduler.Kind.experiment.rawValue: model.selectedTab = .experiment
                default: model.selectedTab = .today
                }
            default:
                break
            }
            if action != UNNotificationDefaultActionIdentifier && action != UNNotificationDismissActionIdentifier {
                Analytics.shared.track(.notificationOpened, ["type": kind, "action": action])
            }
            await Analytics.shared.flush()
            completionHandler()
        }
    }
}
