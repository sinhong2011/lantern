import SwiftUI

/// Master broadcast control — a round beacon, not a switch.
struct BroadcastBeaconStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            beacon(isOn: configuration.isOn)
        }
        .buttonStyle(BroadcastPressStyle())
        .accessibilityLabel("Broadcast")
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .help(configuration.isOn ? "Broadcasting on LAN" : "Broadcast off")
    }

    private func beacon(isOn: Bool) -> some View {
        ZStack {
            if isOn && !reduceMotion {
                BroadcastWaves()
            }

            Circle()
                .fill(isOn ? LanternTheme.live : Color.primary.opacity(0.10))
                .overlay {
                    Circle()
                        .strokeBorder(
                            isOn ? Color.white.opacity(0.28) : Color.primary.opacity(0.14),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: isOn ? LanternTheme.live.opacity(0.5) : .clear,
                    radius: reduceMotion ? 0 : 8
                )
                .frame(width: 28, height: 28)

            Image(systemName: isOn
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 36, height: 36)
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.28, dampingFraction: 0.78),
            value: isOn
        )
    }
}

private struct BroadcastWaves: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let cycle = 1.4
                    let phase = (t / cycle + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(LanternTheme.live.opacity(0.55 * (1 - phase)), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                        .scaleEffect(0.9 + phase * 1.15)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BroadcastPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
