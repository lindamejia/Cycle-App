import SwiftUI
import UIKit

/// Monochrome, typography-led design system. Only `.primary`, `.secondary` and the
/// system background (true black in dark mode) are used: no accent colours.
enum Theme {
    static let gutter: CGFloat = 24
    static let hairline: CGFloat = 1 / max(UIScreen.main.scale, 1)
    static let rule = Color.primary.opacity(0.2)
    static let faint = Color.primary.opacity(0.08)
}

extension Font {
    static let display = Font.system(size: 34, weight: .light)
    static let headline2 = Font.system(size: 26, weight: .regular)
    static let bigNumber = Font.system(size: 30, weight: .light).monospacedDigit()
    static let bodyCalm = Font.system(size: 17, weight: .regular)
    static let caption2Mono = Font.system(size: 12, weight: .regular).monospacedDigit()
}

/// Small caps label: "SLEEP", "WEEK OF 6 OCT".
struct Label2: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(Color.primary.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .regular))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Theme.faint : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.rule, lineWidth: Theme.hairline))
    }
}

/// A toggle-like choice button: filled when selected.
struct ChoiceButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: selected ? .medium : .regular))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
            .background(selected ? Color.primary : (configuration.isPressed ? Theme.faint : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.rule, lineWidth: Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// Full-width list row used for single-choice questions.
struct OptionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack {
                Text(title).font(.bodyCalm)
                Spacer()
                Rectangle()
                    .fill(selected ? Color.primary : Color.clear)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
                    .frame(width: 12, height: 12)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }
}

/// Screen header: small caps label over a large title.
struct ScreenHeader: View {
    let label: String
    let title: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label2(label)
                Spacer()
                if let trailing { Label2(trailing) }
            }
            Text(title).font(.display)
        }
        .padding(.top, 8)
    }
}
