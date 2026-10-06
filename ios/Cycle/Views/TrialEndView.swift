import SwiftUI

/// Day 21: three survey questions, then the fake-door paywall. No payment is ever taken.
struct TrialEndView: View {
    @Environment(AppModel.self) private var model

    enum Step { case mostUseful, disappointment, worthPaying, paywall, thanks }

    @State private var step: Step = .mostUseful
    @State private var mostUseful: String?
    @State private var disappointment: String?
    @State private var worthPaying = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 16)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .mostUseful:
            Label2(L("trial.label"))
            Text(L("trial.q1")).font(.headline2)
            VStack(spacing: 0) {
                ForEach(model.state.insights) { insight in
                    OptionRow(title: insight.title, selected: mostUseful == insight.id) { mostUseful = insight.id }
                }
                OptionRow(title: L("trial.q1.none"), selected: mostUseful == "none") { mostUseful = "none" }
            }

        case .disappointment:
            Label2(L("trial.label"))
            Text(L("trial.q2")).font(.headline2)
            VStack(spacing: 0) {
                ForEach(["very", "somewhat", "not"], id: \.self) { v in
                    OptionRow(title: L("trial.q2.\(v)"), selected: disappointment == v) { disappointment = v }
                }
            }

        case .worthPaying:
            Label2(L("trial.label"))
            Text(L("trial.q3")).font(.headline2)
            TextField(L("trial.q3.placeholder"), text: $worthPaying, axis: .vertical)
                .lineLimit(4...10)
                .focused($textFocused)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.rule, lineWidth: Theme.hairline))

        case .paywall:
            Spacer(minLength: 60)
            Text(L("paywall.title")).font(.system(size: 40, weight: .light))
            Text(L("paywall.price")).font(.system(size: 22, weight: .regular)).monospacedDigit()
            VStack(alignment: .leading, spacing: 10) {
                Text(L("paywall.line1"))
                Text(L("paywall.line2"))
                Text(L("paywall.line3"))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 12)

        case .thanks:
            Spacer(minLength: 60)
            Text(L("paywall.thanks.title")).font(.headline2)
            Text(L("paywall.thanks.body")).font(.bodyCalm)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            switch step {
            case .mostUseful:
                Button(L("common.continue")) { step = .disappointment }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(mostUseful == nil)
            case .disappointment:
                Button(L("common.continue")) { step = .worthPaying }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(disappointment == nil)
            case .worthPaying:
                Button(L("common.continue")) {
                    textFocused = false
                    let insightTitle = model.state.insights.first { $0.id == mostUseful }?.title
                    model.submitTrialSurvey(mostUseful: insightTitle.map { "\(mostUseful ?? ""): \($0)" } ?? "none",
                                            disappointment: disappointment ?? "",
                                            worthPaying: worthPaying)
                    model.paywallShown()
                    step = .paywall
                }
                .buttonStyle(PrimaryButtonStyle())
            case .paywall:
                Button(L("paywall.subscribe")) {
                    Haptics.tap()
                    model.paywallChoice(subscribe: true)
                    step = .thanks
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("paywall.notNow")) {
                    model.paywallChoice(subscribe: false)
                    model.finishTrialFlow()
                }
                .buttonStyle(SecondaryButtonStyle())
            case .thanks:
                Button(L("common.done")) { model.finishTrialFlow() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
