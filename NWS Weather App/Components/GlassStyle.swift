import SwiftUI

extension View {
    /// Primary card surface for the app.
    ///
    /// Uses the *clear* Liquid Glass variant rather than the frosted
    /// `.regular` slab so panels read as genuinely translucent glass floating
    /// over the dark atmospheric background instead of opaque milk-white
    /// cards. A faint white tint keeps a hint of body, and a soft top-down
    /// edge highlight gives the crisp refractive rim that sells the glass.
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .glassEffect(.clear.tint(.white.opacity(0.04)), in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
            )
    }
}
