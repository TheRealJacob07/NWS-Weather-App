import Foundation
internal import Combine

@MainActor
final class WeatherService: ObservableObject {
    @Published var isLoading = false
    @Published var forecast: ForecastSummary?
    @Published var forecastPeriods: [ForecastPeriodSummary] = []
    @Published var hourlyPeriods: [HourlyForecastSummary] = []
    @Published var currentObservation: CurrentObservationSummary?
    @Published var statusMessage = "Weather data will appear after location is loaded."

    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM h:mm a z"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    func loadWeather(latitude: Double, longitude: Double) async {
        isLoading = true
        statusMessage = "Loading weather from NWS..."

        do {
            let pointResponse: NWSPointResponse = try await fetchJSON(
                from: "https://api.weather.gov/points/\(latitude),\(longitude)"
            )

            // Start all three fetches concurrently. Task{} inherits @MainActor so
            // Decodable init stays on the main actor — avoiding nonisolated-context warnings.
            let forecastTask = Task<NWSForecastResponse, Error> {
                try await self.fetchJSON(from: pointResponse.properties.forecast)
            }
            let hourlyTask = Task<NWSForecastResponse, Error> {
                try await self.fetchJSON(from: pointResponse.properties.forecastHourly)
            }
            let stationsTask = Task<NWSObservationStationsResponse, Error> {
                try await self.fetchJSON(from: pointResponse.properties.observationStations)
            }
            let forecastResponse = try await forecastTask.value
            let hourlyResponse = try await hourlyTask.value
            let stationCollection = try await stationsTask.value

            guard let period = forecastResponse.properties.periods.first else {
                forecast = nil
                forecastPeriods = []
                hourlyPeriods = []
                currentObservation = nil
                statusMessage = "No forecast data was returned by NWS."
                isLoading = false
                return
            }

            forecast = ForecastSummary(
                locationName: pointResponse.properties.relativeLocation.properties.city,
                state: pointResponse.properties.relativeLocation.properties.state,
                periodName: period.name,
                temperature: "\(period.temperature)°\(period.temperatureUnit)",
                shortForecast: period.shortForecast,
                wind: "\(period.windSpeed) \(period.windDirection)",
                windSpeed: period.windSpeed,
                windDirection: period.windDirection,
                rain: rainText(for: period)
            )
            forecastPeriods = forecastResponse.properties.periods.prefix(8).map {
                ForecastPeriodSummary(
                    name: $0.name,
                    temperature: "\($0.temperature)°\($0.temperatureUnit)",
                    shortForecast: $0.shortForecast,
                    wind: "\($0.windSpeed) \($0.windDirection)",
                    rain: rainText(for: $0)
                )
            }
            hourlyPeriods = hourlyResponse.properties.periods.prefix(12).map {
                HourlyForecastSummary(
                    name: $0.name,
                    startTime: $0.startTime,
                    temperature: "\($0.temperature)°\($0.temperatureUnit)",
                    shortForecast: $0.shortForecast,
                    rain: rainText(for: $0)
                )
            }

            if let stationURL = stationCollection.observationStationURLs.first {
                let latestObservation: NWSLatestObservationResponse = try await fetchJSON(
                    from: "\(stationURL)/observations/latest"
                )
                currentObservation = CurrentObservationSummary(
                    humidity: humidityText(for: latestObservation.properties.relativeHumidity.value),
                    wind: observationWindText(
                        direction: latestObservation.properties.windDirection.value,
                        speed: latestObservation.properties.windSpeed.value
                    ),
                    barometer: barometerText(for: latestObservation.properties.barometricPressure.value),
                    dewpoint: dewpointText(for: latestObservation.properties.dewpoint.value),
                    visibility: visibilityText(for: latestObservation.properties.visibility.value),
                    lastUpdate: lastUpdatedText(
                        from: latestObservation.properties.timestamp,
                        timeZoneIdentifier: pointResponse.properties.timeZone
                    )
                )
            } else {
                currentObservation = nil
            }
            statusMessage = "Weather loaded."
        } catch {
            forecast = nil
            forecastPeriods = []
            hourlyPeriods = []
            currentObservation = nil
            statusMessage = "Unable to load weather: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func fetchJSON<T: Decodable>(from urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue("NWS Weather App (jacob@example.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw WeatherError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func rainText(for period: ForecastPeriod) -> String {
        guard let value = period.probabilityOfPrecipitation.value else {
            return "Rain chance unavailable"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0))))% chance of rain"
    }

    private func humidityText(for value: Double?) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func observationWindText(direction: Double?, speed: Double?) -> String {
        let cardinal = windCardinalDirection(for: direction)
        guard let speed else { return "\(cardinal) --" }
        let mph = Measurement(value: speed, unit: UnitSpeed.metersPerSecond).converted(to: .milesPerHour).value
        return "\(cardinal) \(mph.formatted(.number.precision(.fractionLength(0)))) mph"
    }

    private func barometerText(for value: Double?) -> String {
        guard let value else { return "--" }
        let mb = Measurement(value: value, unit: UnitPressure.newtonsPerMetersSquared).converted(to: .hectopascals).value
        let inches = mb / 33.8638866667
        return "\(inches.formatted(.number.precision(.fractionLength(2)))) in (\(mb.formatted(.number.precision(.fractionLength(1)))) mb)"
    }

    private func dewpointText(for value: Double?) -> String {
        guard let value else { return "--" }
        let fahrenheit = Measurement(value: value, unit: UnitTemperature.celsius).converted(to: .fahrenheit).value
        return "\(fahrenheit.formatted(.number.precision(.fractionLength(0))))°F (\(value.formatted(.number.precision(.fractionLength(0))))°C)"
    }

    private func visibilityText(for value: Double?) -> String {
        guard let value else { return "--" }
        let miles = Measurement(value: value, unit: UnitLength.meters).converted(to: .miles).value
        return "\(miles.formatted(.number.precision(.fractionLength(2)))) mi"
    }

    private func lastUpdatedText(from timestamp: String, timeZoneIdentifier: String?) -> String {
        guard let date = WeatherService.iso8601Formatter.date(from: timestamp) else { return "--" }
        let formatter = WeatherService.displayFormatter
        if let id = timeZoneIdentifier, let tz = TimeZone(identifier: id) {
            formatter.timeZone = tz
        }
        return formatter.string(from: date)
    }

    private func windCardinalDirection(for degrees: Double?) -> String {
        guard let degrees else { return "--" }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return directions[Int((normalized + 22.5) / 45.0) % directions.count]
    }
}

// MARK: - Summary types consumed by views

struct ForecastSummary {
    let locationName: String
    let state: String
    let periodName: String
    let temperature: String
    let shortForecast: String
    let wind: String
    let windSpeed: String
    let windDirection: String
    let rain: String
}

struct ForecastPeriodSummary: Identifiable {
    let id = UUID()
    let name: String
    let temperature: String
    let shortForecast: String
    let wind: String
    let rain: String
}

struct HourlyForecastSummary: Identifiable {
    let id = UUID()
    let name: String
    let startTime: String
    let temperature: String
    let shortForecast: String
    let rain: String
}

struct CurrentObservationSummary {
    let humidity: String
    let wind: String
    let barometer: String
    let dewpoint: String
    let visibility: String
    let lastUpdate: String
}

// MARK: - Private NWS API types

private enum WeatherError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The weather request URL was invalid."
        case .invalidResponse: return "The weather service returned an invalid response."
        }
    }
}

private struct NWSPointResponse: Decodable {
    let properties: PointProperties
}

private struct PointProperties: Decodable {
    let forecast: String
    let forecastHourly: String
    let observationStations: String
    let timeZone: String?
    let relativeLocation: RelativeLocation
}

private struct RelativeLocation: Decodable {
    let properties: RelativeLocationProperties
}

private struct RelativeLocationProperties: Decodable {
    let city: String
    let state: String
}

private struct NWSForecastResponse: Decodable {
    let properties: ForecastProperties
}

private struct ForecastProperties: Decodable {
    let periods: [ForecastPeriod]
}

private struct ForecastPeriod: Decodable {
    let name: String
    let startTime: String
    let temperature: Int
    let temperatureUnit: String
    let windSpeed: String
    let windDirection: String
    let shortForecast: String
    let probabilityOfPrecipitation: NWSQuantitativeValue
}

private struct NWSQuantitativeValue: Decodable {
    let value: Double?
}

private struct NWSObservationStationsResponse: Decodable {
    let observationStationURLs: [String]
    private enum CodingKeys: String, CodingKey {
        case observationStationURLs = "observationStations"
    }
}

private struct NWSLatestObservationResponse: Decodable {
    let properties: NWSLatestObservationProperties
}

private struct NWSLatestObservationProperties: Decodable {
    let timestamp: String
    let relativeHumidity: NWSQuantitativeValue
    let windDirection: NWSQuantitativeValue
    let windSpeed: NWSQuantitativeValue
    let barometricPressure: NWSQuantitativeValue
    let dewpoint: NWSQuantitativeValue
    let visibility: NWSQuantitativeValue
}
