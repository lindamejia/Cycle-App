import SwiftUI

/// Feed of weekly insights, newest first.
struct InsightsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ScreenHeader(label: L("insights.label"), title: L("insights.title"),
                             trailing: model.isDemo ? L("common.demo") : nil)

                if model.isGeneratingInsight {
                    HStack(spacing: 12) {
                        ProgressView().tint(.secondary)
                        Text(L("insights.generating")).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if let error = model.insightError, !model.isGeneratingInsight {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).foregroundStyle(.secondary)
                        Button(L("common.retry")) {
                            Task { await model.ensureWeeklyInsight() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                if model.state.insights.isEmpty && !model.isGeneratingInsight && model.insightError == nil {
                    Text(L("insights.empty")).foregroundStyle(.secondary)
                }

                ForEach(Array(model.state.insights.enumerated()), id: \.element.id) { index, insight in
                    InsightCard(insight: insight, showForecast: index == 0)
                    Hairline()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
    }
}

struct InsightCard: View {
    @Environment(AppModel.self) private var model
    let insight: Insight
    var showForecast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label2(L("insights.weekOf", Day.date(insight.weekStart).map { Day.display($0, "dMMM") } ?? insight.weekStart))
                Spacer()
                Label2(L("insights.confidence.\(insight.confidence)"))
            }

            Text(insight.title)
                .font(.headline2)
                .fixedSize(horizontal: false, vertical: true)
            Text(insight.body)
                .font(.bodyCalm)
                .fixedSize(horizontal: false, vertical: true)

            if let chart = insight.chart, !chart.points.isEmpty {
                MiniChart(series: chart)
            }

            if !insight.evidence.isEmpty {
                VStack(spacing: 0) {
                    ForEach(insight.evidence, id: \.self) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.label).font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            Text(e.value).font(.subheadline.monospacedDigit())
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Hairline() }
                    }
                }
            }

            if showForecast, !model.weekForecast.isEmpty {
                WeekStrip(days: model.weekForecast)
            }

            HStack(spacing: 10) {
                let feedback = model.state.insightFeedback[insight.id]
                Button(L("insights.useful")) {
                    Haptics.tap()
                    model.setFeedback(insight, useful: true)
                }
                .buttonStyle(ChoiceButtonStyle(selected: feedback == true))
                Button(L("insights.notUseful")) {
                    Haptics.tap()
                    model.setFeedback(insight, useful: false)
                }
                .buttonStyle(ChoiceButtonStyle(selected: feedback == false))
            }
        }
        .onAppear { model.markViewed(insight) }
    }
}

/// The week ahead: one column per day, filled squares for higher load.
struct WeekStrip: View {
    let days: [ForecastDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label2(L("insights.weekAhead"))
            HStack(alignment: .top, spacing: 0) {
                ForEach(days, id: \.date) { d in
                    VStack(spacing: 6) {
                        Text(Day.date(d.date).map { Day.display($0, "EEEEE") } ?? "")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(fill(d.risk))
                            .overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: Theme.hairline))
                            .frame(width: 14, height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let high = days.first(where: { $0.risk == .high }) {
                Text(L("insights.heavyDay",
                       Day.date(high.date).map { Day.display($0, "EEEE") } ?? high.date, high.reason))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fill(_ risk: Risk) -> Color {
        switch risk {
        case .low: return .clear
        case .med: return Color.primary.opacity(0.35)
        case .high: return .primary
        }
    }
}
