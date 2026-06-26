import SwiftUI

/// Apple Weather-style section card: a Liquid Glass slab with a small
/// uppercase caption header, divider, and arbitrary content.
struct WeatherCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }
}

/// Square statistic tile used in the conditions grid. When `accent` is set the
/// icon and a soft corner glow pick up the metric's color, signalling the tile
/// opens an interactive chart.
struct ConditionTile<Detail: View>: View {
    let icon: String
    let title: String
    let value: String
    var accent: Color? = nil
    /// Shown only on interactive tiles as a subtle "expand" affordance.
    var isInteractive: Bool = false
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent ?? .white.opacity(0.6))
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer(minLength: 0)

                if isInteractive {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle((accent ?? .white).opacity(0.55))
                }
            }

            Text(value)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 10)

            Spacer(minLength: 4)

            detail
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        // Tile bodies stay neutral (like Apple Weather) so a warm accent can't
        // tint the glass and blend into the background. The accent lives only
        // in the icon and the chart glyph.
        .glassCard(cornerRadius: 22)
    }
}

extension ConditionTile where Detail == Text {
    init(
        icon: String,
        title: String,
        value: String,
        accent: Color? = nil,
        isInteractive: Bool = false,
        detailText: String
    ) {
        self.init(
            icon: icon,
            title: title,
            value: value,
            accent: accent,
            isInteractive: isInteractive
        ) {
            Text(detailText)
        }
    }
}

/// Subtle scale + dim on press, matching the tactile feel of Apple Weather
/// tiles when they're tapped before expanding.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
