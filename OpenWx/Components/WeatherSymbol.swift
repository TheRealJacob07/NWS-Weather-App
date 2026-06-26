import SwiftUI

/// Single source of truth for mapping NWS forecast text to SF Symbols,
/// mirroring the multicolor symbols used by Apple Weather.
enum WeatherSymbol {
    static func name(for forecastText: String, isDaytime: Bool) -> String {
        let text = forecastText.lowercased()

        if text.contains("thunder") || text.contains("storm") {
            return "cloud.bolt.rain.fill"
        }
        if text.contains("snow") || text.contains("blizzard") { return "cloud.snow.fill" }
        if text.contains("sleet") || text.contains("ice") || text.contains("freezing") { return "cloud.sleet.fill" }
        if text.contains("drizzle") { return "cloud.drizzle.fill" }
        if text.contains("rain") || text.contains("shower") {
            return isDaytime ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        }
        if text.contains("fog") || text.contains("haze") || text.contains("mist") { return "cloud.fog.fill" }
        if text.contains("wind") || text.contains("breezy") || text.contains("blustery") { return "wind" }
        if text.contains("partly") || text.contains("mostly sunny") || text.contains("mostly clear") {
            return isDaytime ? "cloud.sun.fill" : "cloud.moon.fill"
        }
        if text.contains("mostly cloudy") || text.contains("cloud") || text.contains("overcast") {
            return "cloud.fill"
        }
        return isDaytime ? "sun.max.fill" : "moon.stars.fill"
    }

    /// An SF Symbol image configured to render like Apple Weather's icons.
    static func image(for forecastText: String, isDaytime: Bool) -> some View {
        Image(systemName: name(for: forecastText, isDaytime: isDaytime))
            .symbolRenderingMode(.multicolor)
    }
}

/// Maps a Fahrenheit temperature to the hue Apple Weather uses in its range bars.
enum TemperatureColor {
    static func color(for fahrenheit: Int) -> Color {
        switch fahrenheit {
        case ..<15: return Color(red: 0.62, green: 0.80, blue: 0.96)
        case ..<32: return Color(red: 0.40, green: 0.71, blue: 0.93)
        case ..<45: return Color(red: 0.33, green: 0.78, blue: 0.87)
        case ..<58: return Color(red: 0.45, green: 0.84, blue: 0.60)
        case ..<70: return Color(red: 0.75, green: 0.86, blue: 0.39)
        case ..<80: return Color(red: 0.99, green: 0.80, blue: 0.31)
        case ..<92: return Color(red: 0.98, green: 0.59, blue: 0.26)
        default: return Color(red: 0.95, green: 0.36, blue: 0.28)
        }
    }
}
