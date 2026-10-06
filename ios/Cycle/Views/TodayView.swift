import SwiftUI

/// One forecast card, then small monochrome stats. Nothing else.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmPeriod = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(label: L("today.label"), title: Day.display(Date(), "EEEEdMMMM"),
                             trailing: model.isDemo ? L("common.demo") : nil)

                forecastCard

                Hairline()

                stats

                if model.cycleSource == .manual {
                    Button(L("today.periodStarted")) { confirmPeriod = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .refreshable { await model.refreshData() }
        .confirmationDialog(L("today.periodStarted.confirm"), isPresented: $confirmPeriod, titleVisibility: .visible) {
            Button(L("today.periodStarted.yes")) {
                Haptics.tap()
                model.periodStartedToday()
            }
            Button(L("common.cancel"), role: .cancel) {}
        }
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label2(L("today.forecast"))
            if let fc = model.todayForecast {
                Text(fc.headline)
                    .font(.headline2)
                    .fixedSize(horizontal: false, vertical: true)
                if !fc.reasons.isEmpty {
                    Text(fc.reasons.joined(separator: " · "))
                        .font(.bodyCalm)
                        .foregroundStyle(.secondary)
                }
                RiskScale(risk: fc.risk)
            } else if model.isRefreshing {
                ProgressView().tint(.secondary)
            } else {
                Text(L("forecast.headline.nodata")).font(.headline2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.rule, lineWidth: Theme.hairline))
    }

    private var stats: some View {
        let f = model.todayFeatures
        let b = Baselines(features: model.features)
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                         alignment: .leading, spacing: 28) {
            Stat(label: L("stat.sleep"), value: f?.sleepHours?.hoursMinutes,
                 note: b.sleep.map { L("stat.usual", $0.hoursMinutes) })
            Stat(label: L("stat.hrv"), value: f?.hrv.map { L("unit.ms", Int($0.rounded())) },
                 note: b.hrv.map { L("stat.usual", L("unit.ms", Int($0.rounded()))) })
            Stat(label: L("stat.rhr"), value: f?.restingHR.map { L("unit.bpm", Int($0.rounded())) },
                 note: b.restingHR.map { L("stat.usual", L("unit.bpm", Int($0.rounded()))) })
            Stat(label: L("stat.cycle"), value: f?.cycleDay.map { L("stat.cycleDay", $0) },
                 note: f?.phase?.label ?? (model.cycleSource == .none ? L("stat.cycle.notTracked") : nil))
            Stat(label: L("stat.calendar"), value: f.map { L("stat.events", $0.eventCount) },
                 note: f.map { L("stat.evening", $0.eveningEvents + $0.lateEvents) })
        }
    }
}

struct Stat: View {
    let label: String
    let value: String?
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(label)
            Text(value ?? "—").font(.bigNumber)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Three small squares: one filled for low, two for medium, three for high load.
struct RiskScale: View {
    let risk: Risk

    var body: some View {
        let level = risk == .low ? 1 : risk == .med ? 2 : 3
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { i in
                Rectangle()
                    .fill(i <= level ? Color.primary : Color.clear)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: Theme.hairline))
                    .frame(width: 10, height: 10)
            }
            Text(L("risk.\(risk.rawValue)"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
        .accessibilityElement(children: .combine)
    }
}
