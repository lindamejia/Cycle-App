import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = "dark"
    @State private var exportItem: ExportItem?
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(label: L("settings.label"), title: L("settings.title"),
                             trailing: model.isDemo ? L("common.demo") : nil)
                    .padding(.bottom, 24)

                section(L("settings.notifications")) {
                    toggleRow(L("settings.notifications.all"), L("settings.notifications.note"),
                              isOn: Binding(get: { model.state.settings.notificationsEnabled },
                                            set: { v in Task { await model.setNotifications(enabled: v) } }))
                    toggleRow(L("settings.energy"), L("settings.energy.note"),
                              isOn: Binding(get: { model.state.settings.energyCheckEnabled },
                                            set: { v in Task { await model.setEnergyCheck(enabled: v) } }))
                        .disabled(!model.state.settings.notificationsEnabled)
                }

                section(L("settings.display")) {
                    HStack(spacing: 10) {
                        Button(L("settings.dark")) { appearance = "dark"; Haptics.tap() }
                            .buttonStyle(ChoiceButtonStyle(selected: appearance != "light"))
                        Button(L("settings.light")) { appearance = "light"; Haptics.tap() }
                            .buttonStyle(ChoiceButtonStyle(selected: appearance == "light"))
                    }
                    .padding(.vertical, 12)
                }

                section(L("settings.demo")) {
                    toggleRow(L("settings.demo.toggle"), L("settings.demo.note"),
                              isOn: Binding(get: { model.isDemo },
                                            set: { v in Task { await model.setDemoMode(v) } }))
                    if model.isDemo {
                        linkRow(L("settings.demo.preview21")) { model.previewTrialFlow() }
                    }
                }

                section(L("settings.data")) {
                    linkRow(L("settings.export")) {
                        if let url = model.exportData() { exportItem = ExportItem(url: url) }
                    }
                    linkRow(L("settings.delete"), destructive: true) { confirmDelete = true }
                    Link(destination: Config.privacyPolicyURL) {
                        HStack {
                            Text(L("settings.privacy"))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.footnote)
                        }
                        .padding(.vertical, 16)
                    }
                    .foregroundStyle(.primary)
                    .overlay(alignment: .bottom) { Hairline() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let code = model.state.participantCode {
                        Text(L("settings.participant", code))
                    }
                    if model.state.trialDay > 0 {
                        Text(L("settings.trialDay", model.state.trialDay, Config.trialLengthDays))
                    }
                    Text(L("settings.version", Config.appVersion))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog(L("settings.delete.confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("settings.delete.action"), role: .destructive) { delete(localOnly: false) }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.delete.message"))
        }
        .alert(L("settings.delete.failed"), isPresented: $deleteFailed) {
            Button(L("settings.delete.localOnly"), role: .destructive) { delete(localOnly: true) }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.delete.failed.message"))
        }
        .overlay {
            if deleting { ProgressView().tint(.secondary) }
        }
    }

    private func delete(localOnly: Bool) {
        deleting = true
        Task {
            do {
                try await model.deleteAllData(localOnly: localOnly)
            } catch {
                deleteFailed = true
            }
            deleting = false
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label2(title).padding(.bottom, 4)
            Hairline()
            content()
        }
        .padding(.bottom, 28)
    }

    private func toggleRow(_ title: String, _ note: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func linkRow(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .fontWeight(destructive ? .semibold : .regular)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
