import SwiftUI

/// What the app does -> consent -> invite code -> Health + Calendar access -> 4 intake
/// questions -> (last period, if Health has none) -> focus -> notifications -> backfill.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Int, CaseIterable {
        case intro, consent, invite, permissions, age, cycleStatus, changedPlans, triedChange, lastPeriod, focus,
             notifications, reading
    }

    @State private var step: Step = .intro
    @State private var code = ""
    @State private var busy = false
    @State private var errorText: String?

    @State private var ageRange: String?
    @State private var cycleStatus: CycleStatus?
    @State private var changedPlans: String?
    @State private var triedChange: String?
    @State private var focus: Focus?
    @State private var hasHealthFlow = false
    @State private var lastPeriod = Day.add(-14, to: Day.today)
    @State private var cycleLength = 28
    @State private var cycleLengthUnknown = false

    private static let ageRanges = ["18-24", "25-34", "35-44", "45-54", "55+"]
    private static let changedPlansOptions = ["never", "1_2", "several", "often"]
    private static let triedChangeOptions = ["noticed", "couldnt_tell", "no"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: Layout

    private var progress: some View {
        let questionSteps: [Step] = [.age, .cycleStatus, .changedPlans, .triedChange]
        return HStack {
            if step != .intro && step != .reading {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular))
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(L("common.back"))
            }
            Spacer()
            if let i = questionSteps.firstIndex(of: step) {
                Label2(L("onb.questionOf", i + 1, questionSteps.count))
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            Label2(L("onb.intro.label"))
            Text(L("onb.intro.title")).font(.display)
            VStack(alignment: .leading, spacing: 14) {
                Text(L("onb.intro.line1"))
                Text(L("onb.intro.line2"))
                Text(L("onb.intro.line3"))
            }
            .font(.bodyCalm)
            .foregroundStyle(.secondary)

        case .consent:
            Label2(L("onb.consent.label"))
            Text(L("onb.consent.title")).font(.headline2)
            consentBlock(L("onb.consent.reads.title"), L("onb.consent.reads.body"))
            consentBlock(L("onb.consent.stays.title"), L("onb.consent.stays.body"))
            consentBlock(L("onb.consent.stored.title"), L("onb.consent.stored.body"))
            consentBlock(L("onb.consent.test.title"), L("onb.consent.test.body"))
            consentBlock(L("onb.consent.control.title"), L("onb.consent.control.body"))
            Link(L("settings.privacy"), destination: Config.privacyPolicyURL)
                .font(.footnote)
                .underline()
                .foregroundStyle(.primary)

        case .invite:
            Label2(L("onb.invite.label"))
            Text(L("onb.invite.title")).font(.headline2)
            Text(L("onb.invite.body")).foregroundStyle(.secondary)
            TextField(L("onb.invite.placeholder"), text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 28, weight: .light).monospaced())
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Hairline() }
            if !Config.isBackendConfigured {
                Text(L("error.notConfigured")).font(.footnote).foregroundStyle(.secondary)
            }

        case .permissions:
            Label2(L("onb.perm.label"))
            Text(L("onb.perm.title")).font(.headline2)
            Text(L("onb.perm.health")).foregroundStyle(.secondary)
            Text(L("onb.perm.calendar")).foregroundStyle(.secondary)
            Text(L("onb.perm.note")).font(.footnote).foregroundStyle(.secondary)

        case .age:
            question(L("intake.age.q"), options: Self.ageRanges.map { ($0, $0) }, selection: $ageRange)

        case .cycleStatus:
            Text(L("intake.cycle.q")).font(.headline2)
            VStack(spacing: 0) {
                ForEach(CycleStatus.allCases, id: \.self) { s in
                    OptionRow(title: s.label, selected: cycleStatus == s) { cycleStatus = s }
                }
            }

        case .changedPlans:
            question(L("intake.plans.q"),
                     options: Self.changedPlansOptions.map { ($0, L("intake.plans.\($0)")) },
                     selection: $changedPlans)

        case .triedChange:
            question(L("intake.tried.q"),
                     options: Self.triedChangeOptions.map { ($0, L("intake.tried.\($0)")) },
                     selection: $triedChange)

        case .lastPeriod:
            Text(L("onb.period.title")).font(.headline2)
            Text(L("onb.period.body")).foregroundStyle(.secondary)
            DatePicker(L("onb.period.date"), selection: $lastPeriod,
                       in: Day.add(-60, to: Day.today)...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Hairline() }
            Stepper(value: $cycleLength, in: 21...40) {
                HStack {
                    Text(L("onb.period.length"))
                    Spacer()
                    Text(L("onb.period.days", cycleLength)).monospacedDigit()
                }
            }
            .disabled(cycleLengthUnknown)
            .opacity(cycleLengthUnknown ? 0.4 : 1)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Hairline() }
            Toggle(L("onb.period.unsure"), isOn: $cycleLengthUnknown)
                .tint(.primary)
                .padding(.vertical, 8)

        case .focus:
            Text(L("onb.focus.q")).font(.headline2)
            VStack(spacing: 0) {
                ForEach(Focus.allCases, id: \.self) { f in
                    OptionRow(title: f.label, selected: focus == f) { focus = f }
                }
            }

        case .notifications:
            Label2(L("onb.notif.label"))
            Text(L("onb.notif.title")).font(.headline2)
            Text(L("onb.notif.body")).foregroundStyle(.secondary)

        case .reading:
            Label2(L("onb.reading.label"))
            Text(L("onb.reading.title")).font(.headline2)
            ProgressView().tint(.secondary).padding(.top, 8)
        }

        if let errorText {
            Text(errorText).font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            switch step {
            case .intro:
                Button(L("common.continue")) { advance() }.buttonStyle(PrimaryButtonStyle())
                Button(L("onb.intro.demo")) {
                    Task { await model.setDemoMode(true) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            case .consent:
                Button(L("onb.consent.agree")) {
                    model.state.consentAt = Date()
                    model.save()
                    advance()
                }
                .buttonStyle(PrimaryButtonStyle())
            case .invite:
                Button {
                    redeem()
                } label: {
                    if busy { ProgressView() } else { Text(L("common.continue")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || code.trimmingCharacters(in: .whitespaces).count < 4 || !Config.isBackendConfigured)
            case .permissions:
                Button(L("onb.perm.allow")) { requestPermissions() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
            case .notifications:
                Button(L("onb.notif.allow")) {
                    Task {
                        await NotificationScheduler.requestPermission()
                        finish()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("onb.notif.later")) {
                    model.state.settings.notificationsEnabled = false
                    finish()
                }
                .buttonStyle(SecondaryButtonStyle())
            case .reading:
                EmptyView()
            default:
                Button(L("common.continue")) { advance() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue)
            }
        }
    }

    private func consentBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(title)
            Text(body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func question(_ q: String, options: [(String, String)], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(q).font(.headline2).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(options, id: \.0) { option in
                    OptionRow(title: option.1, selected: selection.wrappedValue == option.0) {
                        selection.wrappedValue = option.0
                    }
                }
            }
        }
    }

    // MARK: Flow

    private var canContinue: Bool {
        switch step {
        case .age: return ageRange != nil
        case .cycleStatus: return cycleStatus != nil
        case .changedPlans: return changedPlans != nil
        case .triedChange: return triedChange != nil
        case .focus: return focus != nil
        default: return true
        }
    }

    private func next(after s: Step) -> Step {
        var n = Step(rawValue: s.rawValue + 1) ?? .reading
        if n == .lastPeriod && (cycleStatus != .natural || hasHealthFlow) { n = .focus }
        return n
    }

    private func advance() {
        errorText = nil
        Haptics.tap()
        step = next(after: step)
    }

    private func goBack() {
        errorText = nil
        var p = Step(rawValue: step.rawValue - 1) ?? .intro
        if p == .lastPeriod && (cycleStatus != .natural || hasHealthFlow) { p = .triedChange }
        step = p
    }

    private func redeem() {
        busy = true
        errorText = nil
        Task {
            do {
                try await model.redeemInvite(code.trimmingCharacters(in: .whitespaces).uppercased())
                advance()
            } catch let e as BackendError where e.isInvalidCode {
                errorText = L("onb.invite.invalid")
            } catch {
                errorText = L("onb.invite.failed")
            }
            busy = false
        }
    }

    private func requestPermissions() {
        busy = true
        Task {
            await model.requestHealthAndCalendar()
            hasHealthFlow = await model.hasHealthFlowData()
            busy = false
            advance()
        }
    }

    private func finish() {
        guard let ageRange, let cycleStatus, let changedPlans, let triedChange, let focus else { return }
        step = .reading
        let manual: ManualCycle? = (cycleStatus == .natural && !hasHealthFlow)
            ? ManualCycle(lastPeriodStart: lastPeriod, typicalLength: cycleLengthUnknown ? 28 : cycleLength)
            : nil
        let intake = Intake(ageRange: ageRange, cycleStatus: cycleStatus, changedPlans: changedPlans, triedChange: triedChange)
        Task {
            await model.completeOnboarding(intake: intake, focus: focus, manualCycle: manual)
        }
    }
}
