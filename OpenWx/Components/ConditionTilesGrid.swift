import SwiftUI

/// Two-column grid of square condition tiles, mirroring Apple Weather's
/// Feels Like / Humidity / Wind / Pressure layout.
struct ConditionTilesGrid: View {
    let forecast: ForecastSummary?
    let observation: CurrentObservationSummary
    /// Called when the user taps a tile backed by an hourly trend, so the
    /// parent can flip it open into a full-screen chart. Pressure and
    /// Visibility have no hourly series, so they stay static.
    var onSelectMetric: (WeatherMetric) -> Void = { _ in }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            chartableTile(.temperature) {
                ConditionTile(
                    icon: "thermometer.medium",
                    title: "Feels Like",
                    value: observation.feelsLike,
                    accent: WeatherMetric(.temperature).tint,
                    isInteractive: true,
                    detailText: feelsLikeDetail
                )
            }

            chartableTile(.humidity) {
                ConditionTile(
                    icon: "humidity",
                    title: "Humidity",
                    value: observation.humidity,
                    accent: WeatherMetric(.humidity).tint,
                    isInteractive: true,
                    detailText: "The dew point is \(observation.dewpoint) right now."
                )
            }

            chartableTile(.wind) {
                ConditionTile(
                    icon: "wind",
                    title: "Wind",
                    value: windValue,
                    accent: WeatherMetric(.wind).tint,
                    isInteractive: true
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.fill")
                            .font(.caption2)
                        Text(windDetail)
                    }
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

            chartableTile(.precipitation) {
                ConditionTile(
                    icon: "drop.fill",
                    title: "Precipitation",
                    value: "\(forecast?.precipChance ?? 0)%",
                    accent: WeatherMetric(.precipitation).tint,
                    isInteractive: true,
                    detailText: "Chance of precipitation \(forecast?.periodName.lowercased() ?? "today")."
                )
            }
        }
    }

    /// Wraps a tile in a button that flips it open into its hourly chart.
    private func chartableTile<Content: View>(
        _ kind: WeatherMetric.Kind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            onSelectMetric(WeatherMetric(kind))
        } label: {
            content()
        }
        .buttonStyle(TilePressStyle())
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
        // Use the station's observed temperature, not the forecast period's
        // value (which is today's high or tonight's low — never the actual
        // current air temperature).
        guard observation.temperatureValue != nil else {
            return "Compared to the air temperature."
        }
        return "Actual temperature is \(observation.temperatureText)."
    }

    private var visibilityDetail: String {
        let miles = Double(observation.visibility.replacingOccurrences(of: " mi", with: "")) ?? 0
        if miles >= 9 { return "It's perfectly clear right now." }
        if miles >= 5 { return "Visibility is good." }
        return "Reduced visibility conditions."
    }
}
