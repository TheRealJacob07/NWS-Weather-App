import Foundation
import WidgetKit

/// Snapshot of home-screen essentials, written by the app after every
/// forecast load and read by the home-screen widget through the shared
/// App Group container.
///
/// SETUP: add the "App Groups" capability to BOTH the app target and the
/// widget extension target, using the ID below (change it to match your
/// team's bundle prefix if needed).
struct WidgetSnapshot: Codable {
    static let appGroupID = "group.com.jacobseastrunk.nwsweather"
    static let storageKey = "widget_snapshot_v1"

    let locationName: String
    let temperature: Int
    let high: Int?
    let low: Int?
    let shortForecast: String
    let isDaytime: Bool
    let precipChance: Int
    let alertEvent: String?
    let alertCount: Int
    let aqi: Int?
    let uvIndex: Double?
    let updated: Date
    // Extras for the large widget (optional for decode compatibility).
    let feelsLike: String?
    let humidity: String?
    let wind: String?
    let hourly: [HourlyEntry]?

    struct HourlyEntry: Codable {
        let label: String
        let temperature: Int
        let precipChance: Int
    }

    var highLowText: String {
        var parts: [String] = []
        if let high { parts.append("H:\(high)°") }
        if let low { parts.append("L:\(low)°") }
        return parts.joined(separator: " ")
    }

    /// SF Symbol for the condition text (self-contained so the widget
    /// doesn't need the app's view code).
    var symbolName: String {
        let text = shortForecast.lowercased()
        if text.contains("thunder") || text.contains("storm") { return "cloud.bolt.rain.fill" }
        if text.contains("snow") || text.contains("sleet") { return "snowflake" }
        if text.contains("rain") || text.contains("shower") || text.contains("drizzle") { return "cloud.rain.fill" }
        if text.contains("fog") { return "cloud.fog.fill" }
        if text.contains("cloud") || text.contains("overcast") { return isDaytime ? "cloud.sun.fill" : "cloud.moon.fill" }
        return isDaytime ? "sun.max.fill" : "moon.stars.fill"
    }

    // MARK: - Persistence

    static func save(
        forecast: ForecastSummary?,
        observedTemperature: Int? = nil,
        observation: CurrentObservationSummary? = nil,
        hourly: [HourlyForecastSummary] = [],
        alerts: [WeatherAlertSummary],
        aqi: Int?,
        uv: Double?
    ) {
        guard let forecast else { return }
        let snapshot = WidgetSnapshot(
            locationName: forecast.locationName,
            temperature: observedTemperature ?? forecast.temperature,
            high: forecast.high,
            low: forecast.low,
            shortForecast: forecast.shortForecast,
            isDaytime: forecast.isDaytime,
            precipChance: forecast.precipChance,
            alertEvent: alerts.first?.event,
            alertCount: alerts.count,
            aqi: aqi,
            uvIndex: uv,
            updated: Date(),
            feelsLike: observation?.feelsLike,
            humidity: observation?.humidity,
            wind: observation.map { "\($0.windSpeed) \($0.windDirection)" },
            hourly: hourly.prefix(6).map {
                HourlyEntry(label: $0.timeLabel, temperature: $0.temperature, precipChance: $0.precipChance)
            }
        )

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
