import SwiftUI

/// A condition that can be expanded from a tile into a full-screen, scrubbable
/// chart of its trend over the next ~24 hours (Apple Weather style).
///
/// Only metrics the NWS hourly forecast actually provides are representable
/// here — pressure and visibility have no hourly series, so they never become
/// a `WeatherMetric`.
struct WeatherMetric: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case temperature, humidity, wind, precipitation
        var id: String { rawValue }
    }

    /// How the trend is drawn. Per-metric so the visual matches the data:
    /// smooth gradient area for temperature/humidity, a line for wind, and
    /// discrete bars for precipitation chance.
    enum ChartStyle {
        case area, line, bar
    }

    let kind: Kind
    var id: String { kind.id }

    init(_ kind: Kind) { self.kind = kind }

    var title: String {
        switch kind {
        case .temperature: return "Temperature"
        case .humidity: return "Humidity"
        case .wind: return "Wind"
        case .precipitation: return "Precipitation"
        }
    }

    var icon: String {
        switch kind {
        case .temperature: return "thermometer.medium"
        case .humidity: return "humidity"
        case .wind: return "wind"
        case .precipitation: return "drop.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .temperature: return .orange
        case .humidity: return .teal
        case .wind: return .mint
        case .precipitation: return .cyan
        }
    }

    var style: ChartStyle {
        switch kind {
        case .temperature, .humidity: return .area
        case .wind: return .line
        case .precipitation: return .bar
        }
    }

    /// A short caption describing what the chart shows.
    var caption: String {
        switch kind {
        case .temperature: return "Hourly air temperature forecast."
        case .humidity: return "Hourly relative humidity forecast."
        case .wind: return "Hourly sustained wind forecast."
        case .precipitation: return "Hourly chance of precipitation."
        }
    }

    /// Formats a raw plotted value back into a display string with its unit.
    func format(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        switch kind {
        case .temperature: return "\(rounded)°"
        case .humidity, .precipitation: return "\(rounded)%"
        case .wind: return "\(rounded) mph"
        }
    }

    /// The precipitation axis is always 0–100; others auto-scale to the data.
    var fixedDomain: ClosedRange<Double>? {
        switch kind {
        case .precipitation, .humidity: return 0...100
        default: return nil
        }
    }

    /// Builds the chart series from the hourly forecast, dropping hours that
    /// lack a timestamp or the value this metric needs.
    func series(from hourly: [HourlyForecastSummary]) -> [MetricPoint] {
        hourly.compactMap { hour in
            guard let date = hour.date else { return nil }
            let value: Double?
            switch kind {
            case .temperature: value = Double(hour.temperature)
            case .humidity: value = hour.humidity.map(Double.init)
            case .wind: value = hour.windSpeed
            case .precipitation: value = Double(hour.precipChance)
            }
            guard let value else { return nil }
            return MetricPoint(date: date, value: value)
        }
    }
}

/// A single (time, value) sample plotted on a metric chart. Identified by its
/// timestamp so the series stays stable across re-renders (a random id would
/// reset chart animation and scrub selection every refresh).
struct MetricPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let value: Double
}
