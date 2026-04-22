import SwiftUI

struct AtmosphericBackground: View {
    let style: WeatherBackgroundStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(style.primaryGlow.opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .offset(x: 110, y: -260)

            Circle()
                .fill(style.secondaryGlow.opacity(0.24))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: -140, y: -40)

            Circle()
                .fill(style.accentGlow.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 0, y: 280)
        }
    }
}

struct WeatherBackgroundStyle {
    let gradientColors: [Color]
    let primaryGlow: Color
    let secondaryGlow: Color
    let accentGlow: Color
    let symbolName: String

    init(forecastText: String?) {
        let text = forecastText?.lowercased() ?? ""

        if text.contains("storm") || text.contains("thunder") {
            gradientColors = [
                Color(red: 0.03, green: 0.04, blue: 0.10),
                Color(red: 0.11, green: 0.12, blue: 0.20),
                Color(red: 0.02, green: 0.02, blue: 0.06)
            ]
            primaryGlow = .indigo
            secondaryGlow = .cyan
            accentGlow = .white
            symbolName = "cloud.bolt.rain.fill"
        } else if text.contains("snow") || text.contains("sleet") {
            gradientColors = [
                Color(red: 0.07, green: 0.12, blue: 0.18),
                Color(red: 0.20, green: 0.28, blue: 0.34),
                Color(red: 0.10, green: 0.16, blue: 0.22)
            ]
            primaryGlow = .white
            secondaryGlow = .cyan
            accentGlow = .blue
            symbolName = "snowflake"
        } else if text.contains("rain") || text.contains("showers") {
            gradientColors = [
                Color(red: 0.02, green: 0.09, blue: 0.16),
                Color(red: 0.04, green: 0.18, blue: 0.28),
                Color(red: 0.01, green: 0.05, blue: 0.10)
            ]
            primaryGlow = .blue
            secondaryGlow = .cyan
            accentGlow = .mint
            symbolName = "cloud.rain.fill"
        } else if text.contains("cloud") || text.contains("fog") || text.contains("overcast") {
            gradientColors = [
                Color(red: 0.08, green: 0.10, blue: 0.15),
                Color(red: 0.16, green: 0.19, blue: 0.24),
                Color(red: 0.05, green: 0.07, blue: 0.11)
            ]
            primaryGlow = .gray
            secondaryGlow = .blue
            accentGlow = .white
            symbolName = "cloud.fill"
        } else {
            gradientColors = [
                Color(red: 0.05, green: 0.13, blue: 0.22),
                Color(red: 0.10, green: 0.28, blue: 0.40),
                Color(red: 0.02, green: 0.06, blue: 0.12)
            ]
            primaryGlow = .orange
            secondaryGlow = .yellow
            accentGlow = .cyan
            symbolName = "sun.max.fill"
        }
    }
}
