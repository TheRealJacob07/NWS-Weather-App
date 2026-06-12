import SwiftUI

/// Two-column grid of square condition tiles, mirroring Apple Weather's
/// Feels Like / Humidity / Wind / Pressure layout.
struct ConditionTilesGrid: View {
    let forecast: ForecastSummary?
    let observation: CurrentObservationSummary

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ConditionTile(
                icon: "thermometer.medium",
                title: "Feels Like",
                value: observation.feelsLike,
                detailText: feelsLikeDetail
            )

            ConditionTile(
                icon: "humidity",
                title: "Humidity",
                value: observation.humidity,
                detailText: "The dew point is \(observation.dewpoint) right now."
            )

            ConditionTile(icon: "wind", title: "Wind", value: windValue) {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.fill")
                        .font(.caption2)
                    Text(windDetail)
                }
            }

            ConditionTile(
                icon: "gauge.with.dots.needle.bottom.50percent",
                title: "Pressure",
                value: observation.barometer,
                detailText: "Sea-level barometric pressure."
            )

            ConditionTile(
                icon: "eye",
                title: "Visibility",
                value: observation.visibility,
                detailText: visibilityDetail
            )

            ConditionTile(
                icon: "drop.fill",
                title: "Precipitation",
                value: "\(forecast?.precipChance ?? 0)%",
                detailText: "Chance of precipitation \(forecast?.periodName.lowercased() ?? "today")."
            )
        }
    }

    /// Stations often report null wind (calm or sensor gap) — fall back to
    /// the NWS forecast wind rather than showing "--".
    private var windValue: String {
        if observation.windSpeed != "--" { return observation.windSpeed }
        if let forecast, !forecast.windSpeedText.isEmpty { return forecast.windSpeedText }
        return "Calm"
    }

    private var windDetail: String {
        if observation.windSpeed != "--", observation.windDirection != "--" {
            return "From the \(observation.windDirection)"
        }
        if let forecast, !forecast.windDirectionText.isEmpty {
            return "Forecast: from the \(forecast.windDirectionText)"
        }
        return "No station wind report"
    }

    private var feelsLikeDetail: String {
        guard let forecast else { return "Compared to the air temperature." }
        return "Actual temperature is \(forecast.temperatureText)."
    }

    private var visibilityDetail: String {
        let miles = Double(observation.visibility.replacingOccurrences(of: " mi", with: "")) ?? 0
        if miles >= 9 { return "It's perfectly clear right now." }
        if miles >= 5 { return "Visibility is good." }
        return "Reduced visibility conditions."
    }
}
