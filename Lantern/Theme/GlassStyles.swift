import SwiftUI

// Compatibility shims after theme rewrite.
typealias LanternGlassButtonStyle = LanternButtonStyle

extension View {
    func lanternGlassButton(prominent: Bool = false) -> some View {
        lanternButton(prominent: prominent)
    }

    func lanternGlass(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        lanternSurface(radius: cornerRadius)
    }
}
