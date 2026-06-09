import SwiftUI

struct AtmosphericBackground: View {
    let style: WeatherBackgroundStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(style.primaryGlow.opacity(0.26))
                .frame(width: 320, height: 320)
                .blur(radius: 48)
                .offset(x: 120, y: -280)

            Circle()
                .fill(style.secondaryGlow.opacity(0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: -150, y: -60)

            Circle()
                .fill(style.accentGlow.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 75)
                .offset(x: 10, y: 300)
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
                Color(red: 0.05, green: 0.06, blue: 0.12),
                Color(red: 0.13, green: 0.14, blue: 0.23),
                Color(red: 0.03, green: 0.03, blue: 0.08)
            ]
            primaryGlow = .indigo
            secondaryGlow = .purple
            accentGlow = .white
            symbolName = "cloud.bolt.rain.fill"
        } else if text.contains("snow") || text.contains("sleet") {
            gradientColors = [
                Color(red: 0.16, green: 0.23, blue: 0.32),
                Color(red: 0.28, green: 0.36, blue: 0.44),
                Color(red: 0.12, green: 0.18, blue: 0.26)
            ]
            primaryGlow = .white
            secondaryGlow = .cyan
            accentGlow = .blue
            symbolName = "snowflake"
        } else if text.contains("rain") || text.contains("showers") || text.contains("drizzle") {
            gradientColors = [
                Color(red: 0.13, green: 0.20, blue: 0.29),
                Color(red: 0.20, green: 0.29, blue: 0.38),
                Color(red: 0.08, green: 0.13, blue: 0.20)
            ]
            primaryGlow = .blue
            secondaryGlow = .cyan
            accentGlow = .mint
            symbolName = "cloud.rain.fill"
        } else if text.contains("cloud") || text.contains("fog") || text.contains("overcast") {
            if isDaytime {
                gradientColors = [
                    Color(red: 0.28, green: 0.36, blue: 0.47),
                    Color(red: 0.40, green: 0.47, blue: 0.57),
                    Color(red: 0.20, green: 0.26, blue: 0.36)
                ]
            } else {
                gradientColors = [
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.18, green: 0.21, blue: 0.28),
                    Color(red: 0.07, green: 0.09, blue: 0.14)
                ]
            }
            primaryGlow = .gray
            secondaryGlow = .blue
            accentGlow = .white
            symbolName = "cloud.fill"
        } else if isDaytime {
            gradientColors = [
                Color(red: 0.15, green: 0.38, blue: 0.68),
                Color(red: 0.31, green: 0.55, blue: 0.81),
                Color(red: 0.10, green: 0.26, blue: 0.50)
            ]
            primaryGlow = .orange
            secondaryGlow = .yellow
            accentGlow = .cyan
            symbolName = "sun.max.fill"
        } else {
            gradientColors = [
                Color(red: 0.04, green: 0.06, blue: 0.16),
                Color(red: 0.10, green: 0.13, blue: 0.28),
                Color(red: 0.02, green: 0.03, blue: 0.10)
            ]
            primaryGlow = .indigo
            secondaryGlow = .purple
            accentGlow = .white
            symbolName = "moon.stars.fill"
        }
    }
}
