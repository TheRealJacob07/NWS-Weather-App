import Foundation
internal import Combine

@MainActor
final class WeatherService: ObservableObject {
    @Published var isLoading = false
    @Published var forecast: ForecastSummary?
    @Published var dailyForecasts: [DailyForecastSummary] = []
    @Published var hourlyPeriods: [HourlyForecastSummary] = []
    @Published var currentObservation: CurrentObservationSummary?
    @Published var alerts: [WeatherAlertSummary] = []
    @Published var statusMessage = "Weather data will appear after location is loaded."

    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()

    func loadWeather(latitude: Double, longitude: Double) async {
        isLoading = true
        statusMessage = "Loading weather from NWS..."

        do {
            let pointResponse: NWSPointResponse = try await fetchJSON(
                from: "https://api.weather.gov/points/\(latitude),\(longitude)"
            )
            let timeZone = pointResponse.properties.timeZone.flatMap { TimeZone(identifier: $0) } ?? .current

            // Start all fetches concurrently. Task{} inherits @MainActor so
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
            let alertsTask = Task<NWSAlertResponse?, Never> {
                try? await self.fetchJSON(from: "https://api.weather.gov/alerts/active?point=\(latitude),\(longitude)")
            }
            let forecastResponse = try await forecastTask.value
            let hourlyResponse = try await hourlyTask.value
            let stationCollection = try await stationsTask.value
            let alertResponse = await alertsTask.value

            guard let period = forecastResponse.properties.periods.first else {
                clearWeather(status: "No forecast data was returned by NWS.")
                isLoading = false
                return
            }

            dailyForecasts = makeDailySummaries(from: forecastResponse.properties.periods, timeZone: timeZone)
            hourlyPeriods = makeHourlySummaries(from: hourlyResponse.properties.periods, timeZone: timeZone)
            alerts = makeAlertSummaries(from: alertResponse, timeZone: timeZone)

            let today = dailyForecasts.first
            forecast = ForecastSummary(
                locationName: pointResponse.properties.relativeLocation.properties.city,
                state: pointResponse.properties.relativeLocation.properties.state,
                periodName: period.name,
                temperature: period.temperature,
                temperatureText: "\(period.temperature)°",
                shortForecast: period.shortForecast,
                detailedForecast: period.detailedForecast ?? "",
                wind: "\(period.windSpeed) \(period.windDirection)",
                isDaytime: period.isDaytime,
                precipChance: precipChance(for: period),
                high: today?.high ?? (period.isDaytime ? period.temperature : nil),
                low: today?.low ?? (period.isDaytime ? nil : period.temperature)
            )

            if let stationURL = stationCollection.observationStationURLs.first {
                let latestObservation: NWSLatestObservationResponse = try await fetchJSON(
                    from: "\(stationURL)/observations/latest"
                )
                let props = latestObservation.properties
                currentObservation = CurrentObservationSummary(
                    feelsLike: feelsLikeText(
                        heatIndex: props.heatIndex?.value,
                        windChill: props.windChill?.value,
                        temperature: props.temperature?.value
                    ),
                    humidity: humidityText(for: props.relativeHumidity.value),
                    windSpeed: windSpeedText(for: props.windSpeed.value),
                    windDirection: windCardinalDirection(for: props.windDirection.value),
                    barometer: barometerText(for: props.barometricPressure.value),
                    dewpoint: dewpointText(for: props.dewpoint.value),
                    visibility: visibilityText(for: props.visibility.value),
                    lastUpdate: lastUpdatedText(from: props.timestamp, timeZone: timeZone)
                )
            } else {
                currentObservation = nil
            }
            statusMessage = "Weather loaded."
        } catch {
            clearWeather(status: "Unable to load weather: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Summary builders

    private func clearWeather(status: String) {
        forecast = nil
        dailyForecasts = []
        hourlyPeriods = []
        currentObservation = nil
        alerts = []
        statusMessage = status
    }

    private func makeDailySummaries(from periods: [ForecastPeriod], timeZone: TimeZone) -> [DailyForecastSummary] {
        var summaries: [DailyForecastSummary] = []
        var index = 0

        while index < periods.count && summaries.count < 7 {
            let period = periods[index]
            let dayName: String
            if summaries.isEmpty {
                dayName = "Today"
            } else if let date = Self.iso8601Formatter.date(from: period.startTime) {
                let formatter = Self.weekdayFormatter
                formatter.timeZone = timeZone
                dayName = formatter.string(from: date)
            } else {
                dayName = period.name
            }

            if period.isDaytime {
                let night = (index + 1 < periods.count && !periods[index + 1].isDaytime) ? periods[index + 1] : nil
                summaries.append(
                    DailyForecastSummary(
                        dayName: dayName,
                        shortForecast: period.shortForecast,
                        detailedForecast: period.detailedForecast ?? "",
                        isDaytime: true,
                        high: period.temperature,
                        low: night?.temperature,
                        // Use the daytime period's value so the number matches
                        // NWS forecast briefings (not the day/night maximum).
                        precipChance: precipChance(for: period)
                    )
                )
                index += night == nil ? 1 : 2
            } else {
                // A leading night-only period ("Tonight").
                summaries.append(
                    DailyForecastSummary(
                        dayName: dayName,
                        shortForecast: period.shortForecast,
                        detailedForecast: period.detailedForecast ?? "",
                        isDaytime: false,
                        high: nil,
                        low: period.temperature,
                        precipChance: precipChance(for: period)
                    )
                )
                index += 1
            }
        }
        return summaries
    }

    private func makeHourlySummaries(from periods: [ForecastPeriod], timeZone: TimeZone) -> [HourlyForecastSummary] {
        let formatter = Self.hourFormatter
        formatter.timeZone = timeZone

        return periods.prefix(24).enumerated().map { offset, period in
            let label: String
            if offset == 0 {
                label = "Now"
            } else if let date = Self.iso8601Formatter.date(from: period.startTime) {
                label = formatter.string(from: date)
            } else {
                label = period.name
            }
            return HourlyForecastSummary(
                timeLabel: label,
                temperature: period.temperature,
                temperatureText: "\(period.temperature)°",
                shortForecast: period.shortForecast,
                precipChance: precipChance(for: period),
                isDaytime: period.isDaytime
            )
        }
    }

    private func makeAlertSummaries(from response: NWSAlertResponse?, timeZone: TimeZone) -> [WeatherAlertSummary] {
        guard let response else { return [] }
        return response.features.prefix(5).map { feature in
            let props = feature.properties
            var endsText: String?
            if let raw = props.ends ?? props.expires,
               let date = Self.iso8601Formatter.date(from: raw) {
                let formatter = Self.untilFormatter
                formatter.timeZone = timeZone
                endsText = "Until \(formatter.string(from: date))"
            }
            return WeatherAlertSummary(
                id: feature.id,
                event: props.event,
                headline: props.headline ?? props.event,
                severity: WeatherAlertSummary.Severity(rawValue: props.severity?.lowercased() ?? "") ?? .unknown,
                details: props.description ?? "",
                instruction: props.instruction,
                endsText: endsText
            )
        }
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

    // MARK: - Formatting helpers

    private func precipChance(for period: ForecastPeriod) -> Int {
        guard let value = period.probabilityOfPrecipitation.value else { return 0 }
        return Int(value.rounded())
    }

    private func feelsLikeText(heatIndex: Double?, windChill: Double?, temperature: Double?) -> String {
        let celsius = heatIndex ?? windChill ?? temperature
        guard let celsius else { return "--" }
        let fahrenheit = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: .fahrenheit).value
        return "\(fahrenheit.formatted(.number.precision(.fractionLength(0))))°"
    }

    private func humidityText(for value: Double?) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func windSpeedText(for speed: Double?) -> String {
        guard let speed else { return "--" }
        let mph = Measurement(value: speed, unit: UnitSpeed.metersPerSecond).converted(to: .milesPerHour).value
        return "\(mph.formatted(.number.precision(.fractionLength(0)))) mph"
    }

    private func barometerText(for value: Double?) -> String {
        guard let value else { return "--" }
        let mb = Measurement(value: value, unit: UnitPressure.newtonsPerMetersSquared).converted(to: .hectopascals).value
        let inches = mb / 33.8638866667
        return "\(inches.formatted(.number.precision(.fractionLength(2)))) inHg"
    }

    private func dewpointText(for value: Double?) -> String {
        guard let value else { return "--" }
        let fahrenheit = Measurement(value: value, unit: UnitTemperature.celsius).converted(to: .fahrenheit).value
        return "\(fahrenheit.formatted(.number.precision(.fractionLength(0))))°"
    }

    private func visibilityText(for value: Double?) -> String {
        guard let value else { return "--" }
        let miles = Measurement(value: value, unit: UnitLength.meters).converted(to: .miles).value
        return "\(miles.formatted(.number.precision(.fractionLength(0)))) mi"
    }

    private func lastUpdatedText(from timestamp: String, timeZone: TimeZone) -> String {
        guard let date = WeatherService.iso8601Formatter.date(from: timestamp) else { return "--" }
        let formatter = WeatherService.displayFormatter
        formatter.timeZone = timeZone
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
    let temperature: Int
    let temperatureText: String
    let shortForecast: String
    let detailedForecast: String
    let wind: String
    let isDaytime: Bool
    let precipChance: Int
    let high: Int?
    let low: Int?

    var highLowText: String {
        var parts: [String] = []
        if let high { parts.append("H:\(high)°") }
        if let low { parts.append("L:\(low)°") }
        return parts.joined(separator: "  ")
    }
}

struct DailyForecastSummary: Identifiable {
    let id = UUID()
    let dayName: String
    let shortForecast: String
    let detailedForecast: String
    let isDaytime: Bool
    let high: Int?
    let low: Int?
    let precipChance: Int
}

struct HourlyForecastSummary: Identifiable {
    let id = UUID()
    let timeLabel: String
    let temperature: Int
    let temperatureText: String
    let shortForecast: String
    let precipChance: Int
    let isDaytime: Bool
}

struct WeatherAlertSummary: Identifiable {
    enum Severity: String {
        case extreme, severe, moderate, minor, unknown
    }

    let id: String
    let event: String
    let headline: String
    let severity: Severity
    let details: String
    let instruction: String?
    let endsText: String?
}

struct CurrentObservationSummary {
    let feelsLike: String
    let humidity: String
    let windSpeed: String
    let windDirection: String
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
    let isDaytime: Bool
    let temperature: Int
    let temperatureUnit: String
    let windSpeed: String
    let windDirection: String
    let shortForecast: String
    let detailedForecast: String?
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
    let temperature: NWSQuantitativeValue?
    let heatIndex: NWSQuantitativeValue?
    let windChill: NWSQuantitativeValue?
    let relativeHumidity: NWSQuantitativeValue
    let windDirection: NWSQuantitativeValue
    let windSpeed: NWSQuantitativeValue
    let barometricPressure: NWSQuantitativeValue
    let dewpoint: NWSQuantitativeValue
    let visibility: NWSQuantitativeValue
}

private struct NWSAlertResponse: Decodable {
    let features: [NWSAlertFeature]
}

private struct NWSAlertFeature: Decodable {
    let id: String
    let properties: NWSAlertProperties
}

private struct NWSAlertProperties: Decodable {
    let event: String
    let headline: String?
    let severity: String?
    let description: String?
    let instruction: String?
    let ends: String?
    let expires: String?
}
