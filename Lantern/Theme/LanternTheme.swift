import AppKit
import SwiftUI

enum LanternTheme {
    /// Prefer system accent (BetterDisplay-like) with a calm teal fallback feel via live/pending.
    static let accent = Color(nsColor: .controlAccentColor)
    static let accentMuted = Color(nsColor: .controlAccentColor).opacity(0.14)
    static let live = Color(red: 0.20, green: 0.78, blue: 0.42)
    static let pending = Color(red: 0.95, green: 0.72, blue: 0.20)
    static let danger = Color(red: 0.92, green: 0.34, blue: 0.30)

    static let panelWidth: CGFloat = 320
    static let panelHomeHeight: CGFloat = 440
    static let panelExpandedHeight: CGFloat = 580

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 10
    static let radiusL: CGFloat = 12

    static func portText(_ port: Int) -> String { ":\(port)" }
}

// MARK: - BetterDisplay-style building blocks

struct LanternSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: LanternTheme.radiusL, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LanternTheme.radiusL, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct LanternMenuRow: View {
    let title: String
    var symbol: String? = nil
    var detail: String? = nil
    var chevron: Bool = true
    var destructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(destructive ? LanternTheme.danger : Color.secondary)
                        .frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(destructive ? LanternTheme.danger : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.55))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LanternPrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(LanternTheme.accent, in: RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
    }
}

struct LanternFieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct LanternButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var minWidth: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: minWidth)
            .padding(.horizontal, minWidth > 0 ? 12 : 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent
                          ? LanternTheme.accent.opacity(configuration.isPressed ? 0.85 : 1)
                          : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
            }
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.9))
    }
}

extension View {
    func lanternField() -> some View { modifier(LanternFieldSurface()) }
    func lanternButton(prominent: Bool = false, minWidth: CGFloat = 0) -> some View {
        buttonStyle(LanternButtonStyle(prominent: prominent, minWidth: minWidth))
    }
    /// Compatibility for older call sites.
    func lanternSurface(radius: CGFloat = LanternTheme.radiusL, padded: Bool = false) -> some View {
        padding(padded ? 12 : 0)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
