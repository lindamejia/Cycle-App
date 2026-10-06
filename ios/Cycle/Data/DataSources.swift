import Foundation

/// Where daily health data comes from: Apple Health, or the demo generator.
protocol HealthDataSource: AnyObject {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    /// Day key -> aggregated health values for every day in [from, to).
    func healthDays(from: Date, to: Date) async -> [String: HealthDay]
}

/// Where calendar events come from: EventKit, or the demo generator.
protocol CalendarDataSource: AnyObject {
    func requestAccess() async -> Bool
    func events(from: Date, to: Date) -> [CalendarEvent]
}
