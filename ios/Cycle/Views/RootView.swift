import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.onboardingComplete {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .fullScreenCover(isPresented: $model.showTrialFlow) {
            TrialEndView()
                .environment(model)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TodayView()
                .tabItem { Label(L("tab.today"), systemImage: "circle.lefthalf.filled") }
                .tag(AppTab.today)
            InsightsView()
                .tabItem { Label(L("tab.insights"), systemImage: "chart.xyaxis.line") }
                .tag(AppTab.insights)
            ExperimentView()
                .tabItem { Label(L("tab.experiment"), systemImage: "plusminus") }
                .tag(AppTab.experiment)
            SettingsView()
                .tabItem { Label(L("tab.settings"), systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
        .onChange(of: model.selectedTab, initial: true) { _, tab in
            Haptics.soft()
            Analytics.shared.track(.screenView, ["screen": tab.rawValue])
        }
    }
}
