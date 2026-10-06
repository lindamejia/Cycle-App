import SwiftUI

/// From week 2: one suggested 10-day experiment (or pick one), daily yes/no check-in,
/// and an honest before/after result.
struct ExperimentView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmKind: ExperimentKind?
    @State private var confirmStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(label: L("exp.label"), title: L("exp.title"),
                             trailing: model.isDemo ? L("common.demo") : nil)

                if let active = model.state.activeExperiment {
                    ActiveExperimentView(experiment: active, onStop: { confirmStop = true })
                } else if !model.experimentsUnlocked {
                    locked
                } else {
                    if let last = model.state.experiments.last, let result = last.result {
                        ResultCard(experiment: last, result: result)
                        Hairline()
                    }
                    offer
                }

                let finished = model.state.experiments.filter { $0.result != nil }.dropLast()
                if model.state.activeExperiment == nil, !finished.isEmpty {
                    Label2(L("exp.earlier"))
                    ForEach(Array(finished.reversed())) { e in
                        if let r = e.result { ResultCard(experiment: e, result: r) }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .confirmationDialog(confirmKind?.title ?? "", isPresented: Binding(
            get: { confirmKind != nil }, set: { if !$0 { confirmKind = nil } }), titleVisibility: .visible) {
            Button(L("exp.start.confirm", Config.experimentLengthDays)) {
                if let kind = confirmKind {
                    Haptics.tap()
                    let suggested = model.suggestedExperiment?.kind == kind
                    Task { await model.startExperiment(kind, source: suggested ? "suggested" : "picked") }
                }
                confirmKind = nil
            }
            Button(L("common.cancel"), role: .cancel) { confirmKind = nil }
        } message: {
            Text(confirmKind?.detail ?? "")
        }
        .confirmationDialog(L("exp.stop.confirm"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(L("exp.stop"), role: .destructive) { Task { await model.stopExperiment() } }
            Button(L("common.cancel"), role: .cancel) {}
        }
    }

    private var locked: some View {
        let daysLeft = max(0, Config.experimentUnlockDay - model.state.trialDay)
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("exp.locked.title")).font(.headline2)
            Text(L("exp.locked.body", daysLeft)).foregroundStyle(.secondary)
            Hairline().padding(.vertical, 6)
            ForEach(ExperimentKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                    Text(kind.detail).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var offer: some View {
        let suggestion = model.suggestedExperiment
        if let s = suggestion {
            VStack(alignment: .leading, spacing: 14) {
                Label2(L("exp.suggested"))
                Text(s.kind.title).font(.headline2)
                Text(s.reason).font(.bodyCalm)
                Text(s.kind.detail).font(.footnote).foregroundStyle(.secondary)
                Button(L("exp.start", Config.experimentLengthDays)) { confirmKind = s.kind }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .onAppear { model.markExperimentOffered(s.kind, insightID: s.insightID) }
        }

        VStack(alignment: .leading, spacing: 0) {
            Label2(suggestion == nil ? L("exp.pick") : L("exp.orPick")).padding(.bottom, 8)
            ForEach(ExperimentKind.allCases.filter { $0 != suggestion?.kind }) { kind in
                Button {
                    confirmKind = kind
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title).foregroundStyle(.primary)
                        Text(kind.detail).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Hairline() }
            }
        }
    }
}

struct ActiveExperimentView: View {
    @Environment(AppModel.self) private var model
    let experiment: Experiment
    let onStop: () -> Void

    var body: some View {
        let today = Date()
        let dayNumber = min(experiment.dayNumber(on: today), experiment.length)
        let todayKey = Day.key(today)

        VStack(alignment: .leading, spacing: 20) {
            Label2(L("exp.dayOf", dayNumber, experiment.length))
            Text(experiment.kind.title).font(.headline2)
            Text(experiment.kind.detail).foregroundStyle(.secondary)

            // One segment per day: filled = yes, outlined = no, faint = not answered.
            HStack(spacing: 4) {
                ForEach(0..<experiment.length, id: \.self) { i in
                    let key = Day.key(Day.add(i, to: experiment.start))
                    let answer = experiment.checkins[key]
                    Rectangle()
                        .fill(answer == true ? Color.primary : Color.clear)
                        .overlay(Rectangle().stroke(Color.primary.opacity(answer == nil ? 0.2 : 0.7), lineWidth: 1))
                        .frame(height: 18)
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 12) {
                Label2(L("exp.today"))
                Text(experiment.kind.question).font(.bodyCalm)
                let answer = experiment.checkins[todayKey]
                HStack(spacing: 10) {
                    Button(L("common.yes")) {
                        Haptics.tap()
                        model.checkIn(experimentID: experiment.id, did: true, source: "app")
                    }
                    .buttonStyle(ChoiceButtonStyle(selected: answer == true))
                    Button(L("common.no")) {
                        Haptics.tap()
                        model.checkIn(experimentID: experiment.id, did: false, source: "app")
                    }
                    .buttonStyle(ChoiceButtonStyle(selected: answer == false))
                }
                Text(L("exp.noPressure")).font(.footnote).foregroundStyle(.secondary)
            }

            Button(L("exp.stop"), action: onStop)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
}

struct ResultCard: View {
    let experiment: Experiment
    let result: ExperimentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label2(L("exp.result"))
            Text(experiment.kind.title).font(.headline2)

            HStack(alignment: .top, spacing: 0) {
                column(L("exp.before"), result.before, result.beforeDays)
                column(L("exp.during"), result.during, result.duringDays)
            }

            Text(verdictText).font(.bodyCalm).fixedSize(horizontal: false, vertical: true)
            Text(L("exp.caveat")).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func column(_ title: String, _ value: Double?, _ days: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(title)
            Text(value.map(result.metric.format) ?? "—").font(.bigNumber)
            Text(L("exp.days", days)).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verdictText: String {
        switch result.verdict {
        case .insufficientData:
            return L("exp.verdict.insufficient", ExperimentEngine.minimumDays)
        case .unclear:
            return L("exp.verdict.unclear")
        case .clear:
            guard let b = result.before, let d = result.during else { return L("exp.verdict.unclear") }
            let key = d > b ? "exp.verdict.higher" : "exp.verdict.lower"
            return L(key, result.metric.label, result.metric.formatDelta(d - b))
        }
    }
}
