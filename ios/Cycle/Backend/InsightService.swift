import Foundation

/// Sends the weekly summary to the `weekly-insight` Edge Function and decodes the result.
enum InsightService {
    private struct Response: Decodable {
        let id: String
        let weekStart: String
        let insightTitle: String
        let insightBody: String
        let evidence: [Evidence]
        let chartSeries: ChartSeries?
        let confidence: String
        let weekForecast: [ForecastDay]
        let suggestedExperiment: SuggestedExperiment?

        enum CodingKeys: String, CodingKey {
            case id, evidence, confidence
            case weekStart = "week_start"
            case insightTitle = "insight_title"
            case insightBody = "insight_body"
            case chartSeries = "chart_series"
            case weekForecast = "week_forecast"
            case suggestedExperiment = "suggested_experiment"
        }
    }

    static func generate(_ summary: WeeklySummary) async throws -> Insight {
        let body = try summary.encoded()
        let data = try await SupabaseClient.shared.invokeFunction("weekly-insight", body: body)
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw BackendError.decoding }
        return Insight(id: r.id, weekStart: r.weekStart, createdAt: Date(), title: r.insightTitle,
                       body: r.insightBody, evidence: r.evidence, chart: r.chartSeries,
                       confidence: r.confidence, weekForecast: r.weekForecast,
                       suggestedExperiment: r.suggestedExperiment)
    }
}
