import SwiftUI

/// Compact dBZ / velocity color scale shown on the radar map, like the
/// scales in RadarScope or MyRadar. Tap to collapse into a small chip.
struct RadarLegend: View {
    let product: RadarProduct
    let showsLightning: Bool

    @AppStorage("radar_legend_collapsed") private var isCollapsed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isCollapsed.toggle()
            }
        } label: {
            if isCollapsed {
                collapsedChip
            } else {
                expandedScale
            }
        }
        .buttonStyle(.plain)
        // Material, not glassEffect: the legend sits over the live map and
        // re-renders with product/timeline changes — keeping it off the
        // glass Metal pipeline avoids the multisample-resolve crash.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        }
    }

    private var collapsedChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.below.square.filled.and.square")
                .font(.caption2.weight(.bold))
            Text(scaleTitle)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var expandedScale: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(scaleTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 8)

                if showsLightning {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text("GLM")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }

            LinearGradient(
                stops: gradientStops,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxWidth: .infinity)
            .frame(height: 7)
            .clipShape(Capsule())

            HStack {
                ForEach(tickLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                    if label != tickLabels.last { Spacer(minLength: 0) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - Per-product scales

    private var scaleTitle: String {
        switch product {
        case .velocity: return "Velocity (kt)"
        case .echoTops: return "Echo Tops (kft)"
        default: return "Reflectivity (dBZ)"
        }
    }

    private var gradientStops: [Gradient.Stop] {
        switch product {
        case .velocity:
            // Inbound (toward radar, green) → outbound (away, red)
            return [
                .init(color: Color(red: 0.05, green: 0.55, blue: 0.10), location: 0.0),
                .init(color: Color(red: 0.35, green: 0.85, blue: 0.35), location: 0.35),
                .init(color: Color(red: 0.55, green: 0.55, blue: 0.55), location: 0.5),
                .init(color: Color(red: 0.95, green: 0.45, blue: 0.35), location: 0.65),
                .init(color: Color(red: 0.60, green: 0.05, blue: 0.05), location: 1.0)
            ]
        case .echoTops:
            return [
                .init(color: Color(red: 0.30, green: 0.55, blue: 0.95), location: 0.0),
                .init(color: Color(red: 0.25, green: 0.80, blue: 0.75), location: 0.3),
                .init(color: Color(red: 0.95, green: 0.85, blue: 0.25), location: 0.6),
                .init(color: Color(red: 0.90, green: 0.30, blue: 0.20), location: 0.85),
                .init(color: Color(red: 0.75, green: 0.25, blue: 0.90), location: 1.0)
            ]
        default:
            // NOAA RIDGE reflectivity curve mapped linearly 10–70 dBZ so the
            // meaningful colors fill the entire bar.
            return [
                .init(color: Color(red: 0.29, green: 0.46, blue: 0.65), location: 0.0),   // 10 dBZ
                .init(color: Color(red: 0.25, green: 0.80, blue: 0.45), location: 0.17),  // 20
                .init(color: Color(red: 0.05, green: 0.69, blue: 0.07), location: 0.33),  // 30
                .init(color: Color(red: 0.04, green: 0.45, blue: 0.05), location: 0.45),  // ~37
                .init(color: Color(red: 0.97, green: 0.84, blue: 0.05), location: 0.55),  // ~43
                .init(color: Color(red: 0.97, green: 0.60, blue: 0.04), location: 0.67),  // 50
                .init(color: Color(red: 0.90, green: 0.02, blue: 0.02), location: 0.80),  // ~58
                .init(color: Color(red: 0.95, green: 0.55, blue: 0.95), location: 0.92),  // ~65
                .init(color: Color(red: 0.45, green: 0.00, blue: 0.85), location: 1.0)    // 70+
            ]
        }
    }

    private var tickLabels: [String] {
        switch product {
        case .velocity: return ["-100", "-50", "0", "+50", "+100"]
        case .echoTops: return ["10", "25", "40", "55", "70"]
        default: return ["10", "20", "30", "40", "50", "60", "70"]
        }
    }
}
