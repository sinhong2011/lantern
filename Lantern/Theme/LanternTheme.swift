import AppKit
import SwiftUI

enum LanternTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let accentMuted = Color(nsColor: .controlAccentColor).opacity(0.14)
    static let live = Color(red: 0.20, green: 0.78, blue: 0.42)
    static let pending = Color(red: 0.95, green: 0.72, blue: 0.20)
    static let danger = Color(red: 0.92, green: 0.34, blue: 0.30)

    static let panelWidth: CGFloat = 360
    static let panelHomeHeight: CGFloat = 420
    static let panelExpandedHeight: CGFloat = 560
    static let panelPadding: CGFloat = 20
    static let fieldPaddingH: CGFloat = 12
    static let fieldPaddingV: CGFloat = 10

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 10
    static let radiusL: CGFloat = 12

    static func portText(_ port: Int) -> String {
        port == 80 ? "" : ":\(port)"
    }
}

// MARK: - System vibrancy (matches menu bar / BetterDisplay)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct LanternSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: LanternTheme.radiusL, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LanternTheme.radiusL, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: LanternTheme.radiusL, style: .continuous))
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
    var danger: Bool = false

    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LanternTheme.fieldPaddingH)
            .padding(.vertical, LanternTheme.fieldPaddingV)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                    .strokeBorder(
                        danger ? LanternTheme.danger.opacity(0.7) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous))
    }
}

/// Input + leading/trailing chrome that hugs its control height (never fills leftover panel space).
struct LanternCompoundField<Leading: View, Field: View, Trailing: View>: View {
    var danger: Bool = false
    var leading: Leading
    var field: Field
    var trailing: Trailing

    init(
        danger: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder field: () -> Field,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.danger = danger
        self.leading = leading()
        self.field = field()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
            field
                .textFieldStyle(.plain)
                .padding(.leading, LanternTheme.fieldPaddingH)
                .padding(.trailing, 8)
                .padding(.vertical, LanternTheme.fieldPaddingV)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                .strokeBorder(
                    danger ? LanternTheme.danger.opacity(0.7) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous))
    }
}

extension LanternCompoundField where Leading == EmptyView {
    init(
        danger: Bool = false,
        @ViewBuilder field: () -> Field,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(danger: danger, leading: { EmptyView() }, field: field, trailing: trailing)
    }
}

struct LanternFieldAccessory: View {
    var emphasized: Bool = false
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, LanternTheme.fieldPaddingH)
            .padding(.vertical, LanternTheme.fieldPaddingV)
            .background(Color.primary.opacity(emphasized ? 0.07 : 0.05))
    }
}

struct LanternButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var destructive: Bool = false
    var minWidth: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(minWidth: minWidth)
            .padding(.horizontal, minWidth > 0 ? 12 : 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: LanternTheme.radiusS, style: .continuous)
                    .fill(fillColor(pressed: configuration.isPressed))
            }
            .foregroundStyle(foregroundColor)
    }

    private func fillColor(pressed: Bool) -> Color {
        if destructive {
            return LanternTheme.danger.opacity(pressed ? 0.85 : 1)
        }
        if prominent {
            return LanternTheme.accent.opacity(pressed ? 0.85 : 1)
        }
        return Color.primary.opacity(pressed ? 0.14 : 0.08)
    }

    private var foregroundColor: Color {
        if destructive { return Color.white }
        if prominent { return Color.white }
        return Color.primary.opacity(0.9)
    }
}

extension View {
    func lanternField(danger: Bool = false) -> some View { modifier(LanternFieldSurface(danger: danger)) }
    func lanternButton(prominent: Bool = false, destructive: Bool = false, minWidth: CGFloat = 0) -> some View {
        buttonStyle(LanternButtonStyle(prominent: prominent, destructive: destructive, minWidth: minWidth))
    }
    func lanternSurface(radius: CGFloat = LanternTheme.radiusL, padded: Bool = false) -> some View {
        padding(padded ? 12 : 0)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }

    func lanternPanelBackground() -> some View {
        background {
            VisualEffectBackground(material: .menu, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}
