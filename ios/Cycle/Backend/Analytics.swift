import Foundation

enum AnalyticsEvent: String {
    case appOpen = "app_open"
    case screenView = "screen_view"
    case insightViewed = "insight_viewed"
    case insightFeedback = "insight_feedback"
    case energyCheckin = "energy_checkin"
    case notificationOpened = "notification_opened"
    case experimentOffered = "experiment_offered"
    case experimentStarted = "experiment_started"
    case experimentCheckin = "experiment_checkin"
    case experimentCompleted = "experiment_completed"
    case paywallShown = "paywall_shown"
    case paywallSubscribeTap = "paywall_subscribe_tap"
    case paywallDismiss = "paywall_dismiss"
    case surveyAnswer = "survey_answer"
    case dataDeleted = "data_deleted"
}

/// Pseudonymous analytics and survey answers. Queued on device (survives being offline),
/// sent in batches when the app is opened or backgrounded. Off in demo mode.
final class Analytics {
    static let shared = Analytics()

    struct QueuedEvent: Codable {
        var id: String
        var name: String
        var properties: [String: String]
        var occurredAt: Date
        var localDate: String
    }

    struct QueuedAnswer: Codable {
        var survey: String
        var questionID: String
        var answer: String
    }

    private struct Queue: Codable {
        var events: [QueuedEvent] = []
        var answers: [QueuedAnswer] = []
    }

    /// Set by AppModel: false in demo mode.
    var enabled = false
    var participantID: String?

    private let lock = NSLock()
    private var queue: Queue
    private let store = LocalStore(namespace: "analytics")
    private var isFlushing = false

    private init() {
        queue = store.load(Queue.self, "queue") ?? Queue()
    }

    func track(_ event: AnalyticsEvent, _ properties: [String: String] = [:]) {
        guard enabled else { return }
        let now = Date()
        let e = QueuedEvent(id: UUID().uuidString, name: event.rawValue, properties: properties,
                            occurredAt: now, localDate: Day.key(now))
        lock.withLock {
            queue.events.append(e)
            if queue.events.count > 5000 { queue.events.removeFirst(queue.events.count - 5000) }
            store.save(queue, "queue")
        }
    }

    /// Survey answers go to the survey_answers table; a survey_answer event is logged too.
    /// Free-text answers are not copied into the event.
    func answer(survey: String, question: String, answer: String, freeText: Bool = false) {
        guard enabled else { return }
        lock.withLock {
            queue.answers.append(QueuedAnswer(survey: survey, questionID: question, answer: answer))
            store.save(queue, "queue")
        }
        var props = ["survey": survey, "question_id": question]
        if !freeText { props["answer"] = answer }
        track(.surveyAnswer, props)
    }

    func flush() async {
        guard enabled, let participantID, Config.isBackendConfigured else { return }
        let batch: (events: [QueuedEvent], answers: [QueuedAnswer])? = lock.withLock {
            if isFlushing { return nil }
            isFlushing = true
            return (Array(queue.events.prefix(500)), queue.answers)
        }
        guard let batch else { return }
        defer { lock.withLock { isFlushing = false } }

        var sentAnswers = 0
        for a in batch.answers {
            do {
                _ = try await SupabaseClient.shared.rpc("submit_survey_answer", params: [
                    "p_survey": a.survey, "p_question_id": a.questionID, "p_answer": a.answer,
                ])
                sentAnswers += 1
            } catch { break }
        }

        var sentEvents = 0
        if !batch.events.isEmpty {
            let iso = ISO8601DateFormatter()
            let rows: [[String: Any]] = batch.events.map { e in
                [
                    "client_event_id": e.id,
                    "participant_id": participantID,
                    "name": e.name,
                    "properties": e.properties,
                    "occurred_at": iso.string(from: e.occurredAt),
                    "local_date": e.localDate,
                ]
            }
            if let json = try? JSONSerialization.data(withJSONObject: rows),
               (try? await SupabaseClient.shared.insert("events?on_conflict=client_event_id", json: json)) != nil {
                sentEvents = batch.events.count
            }
        }

        let sentIDs = Set(batch.events.prefix(sentEvents).map(\.id))
        lock.withLock {
            queue.answers.removeFirst(min(sentAnswers, queue.answers.count))
            queue.events.removeAll { sentIDs.contains($0.id) }
            store.save(queue, "queue")
        }
    }

    func clear() {
        lock.withLock {
            queue = Queue()
            store.wipe()
        }
    }
}
