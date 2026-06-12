import SwiftUI

/// Deep-space dark atmospheric backdrop: condition-tinted gradient with
/// soft aurora glows. Tuned dark so Liquid Glass surfaces float above it.
struct AtmosphericBackground: View {
    let style: WeatherBackgroundStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )

            // Aurora glows
            Circle()
                .fill(style.primaryGlow.opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 56)
                .offset(x: 130, y: -290)

            Circle()
                .fill(style.secondaryGlow.opacity(0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -160, y: -40)

            Circle()
                .fill(style.accentGlow.opacity(0.09))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 20, y: 320)

            // Subtle horizon sheen for depth
            LinearGradient(
                colors: [.clear, style.primaryGlow.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .animation(.easeInOut(duration: 0.8), value: style.gradientColors)
    }
}

struct WeatherBackgroundStyle {
    let gradientColors: [Color]
    let primaryGlow: Color
    let secondaryGlow: Color
    let accentGlow: Color
    let symbolName: String

    init(forecastText: String?, isDaytime: Bool = true) {
        let text = forecastText?.lowercased() ?? ""

        if text.contains("storm") || text.contains("thunder") {
            gradientColors = [
                Color(red: 0.04, green: 0.05, blue: 0.10),
                Color(red: 0.10, green: 0.10, blue: 0.19),
                Color(red: 0.02, green: 0.02, blue: 0.06)
            ]
            primaryGlow = .indigo
            secondaryGlow = .purple
            accentGlow = .white
            symbolName = "cloud.bolt.rain.fill"
        } else if text.contains("snow") || text.contains("sleet") {
            gradientColors = [
                Color(red: 0.08, green: 0.12, blue: 0.19),
                Color(red: 0.15, green: 0.21, blue: 0.29),
                Color(red: 0.05, green: 0.08, blue: 0.14)
            ]
            primaryGlow = .white
            secondaryGlow = .cyan
            accentGlow = .blue
            symbolName = "snowflake"
        } else if text.contains("rain") || text.contains("showers") || text.contains("drizzle") {
            gradientColors = [
                Color(red: 0.06, green: 0.10, blue: 0.17),
                Color(red: 0.11, green: 0.17, blue: 0.25),
                Color(red: 0.04, green: 0.07, blue: 0.12)
            ]
            primaryGlow = .blue
            secondaryGlow = .cyan
            accentGlow = .mint
            symbolName = "cloud.rain.fill"
        } else if text.contains("cloud") || text.contains("fog") || text.contains("overcast") {
            if isDaytime {
                gradientColors = [
                    Color(red: 0.12, green: 0.16, blue: 0.24),
                    Color(red: 0.19, green: 0.24, blue: 0.32),
                    Color(red: 0.08, green: 0.11, blue: 0.17)
                ]
            } else {
                gradientColors = [
                    Color(red: 0.07, green: 0.08, blue: 0.13),
                    Color(red: 0.12, green: 0.14, blue: 0.20),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ]
            }
            primaryGlow = .gray
            secondaryGlow = .blue
            accentGlow = .white
            symbolName = "cloud.fill"
        } else if isDaytime {
            gradientColors = [
                Color(red: 0.06, green: 0.17, blue: 0.34),
                Color(red: 0.12, green: 0.28, blue: 0.48),
                Color(red: 0.04, green: 0.10, blue: 0.22)
            ]
            primaryGlow = .orange
            secondaryGlow = .cyan
            accentGlow = .teal
            symbolName = "sun.max.fill"
        } else {
            gradientColors = [
                Color(red: 0.03, green: 0.04, blue: 0.12),
                Color(red: 0.07, green: 0.09, blue: 0.21),
                Color(red: 0.01, green: 0.02, blue: 0.07)
            ]
            primaryGlow = .indigo
            secondaryGlow = .purple
            accentGlow = .white
            symbolName = "moon.stars.fill"
        }
    }
}
