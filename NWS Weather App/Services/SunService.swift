import Foundation
import CoreLocation
internal import Combine

struct SunSnapshot {
    let uvIndex: Double
    let uvMaxToday: Double
    let sunrise: Date
    let sunset: Date
    let daylightSeconds: Double
    let timeZone: TimeZone

    var uvCategory: String {
        switch uvIndex {
        case ..<3: return "Low"
        case ..<6: return "Moderate"
        case ..<8: return "High"
        case ..<11: return "Very High"
        default: return "Extreme"
        }
    }

    /// 0…1 along a 0–11+ UV gauge.
    var uvGaugeRatio: Double { min(1.0, uvIndex / 11.0) }

    var protectionAdvice: String {
        switch uvIndex {
        case ..<3: return "No protection needed for most people."
        case ..<6: return "Wear sunscreen if outside for a while."
        case ..<8: return "SPF 30+, hat, and shade at midday."
        case ..<11: return "Limit midday sun. SPF 50+ recommended."
        default: return "Avoid midday sun — burns in minutes."
        }
    }

    /// Rough unprotected burn-time estimate for fair skin.
    var burnTimeText: String {
        switch uvIndex {
        case ..<1: return "Minimal risk"
        case ..<3: return "~60+ min to burn"
        case ..<6: return "~30–45 min to burn"
        case ..<8: return "~15–25 min to burn"
        case ..<11: return "~10–15 min to burn"
        default: return "<10 min to burn"
        }
    }

    /// 0…1 position of the sun between sunrise and sunset (clamped).
    var dayProgress: Double {
        let total = sunset.timeIntervalSince(sunrise)
        guard total > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(sunrise) / total))
    }

    var daylightText: String {
        let hours = Int(daylightSeconds) / 3600
        let minutes = (Int(daylightSeconds) % 3600) / 60
        return "\(hours) hr \(minutes) min"
    }
}

/// UV index and sun-cycle data from the free Open-Meteo forecast API.
@MainActor
final class SunService: ObservableObject {
    @Published private(set) var snapshot: SunSnapshot?

    func load(coordinate: CLLocationCoordinate2D) async {
        let urlString = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)"
            + "&current=uv_index&daily=uv_index_max,sunrise,sunset,daylight_duration"
            + "&forecast_days=1&timeformat=unixtime&timezone=auto"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await NetworkSessions.api.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
            let payload = try JSONDecoder().decode(OpenMeteoSun.self, from: data)

            guard let sunriseEpoch = payload.daily.sunrise.first,
                  let sunsetEpoch = payload.daily.sunset.first else { return }

            snapshot = SunSnapshot(
                uvIndex: payload.current.uv_index ?? 0,
                uvMaxToday: payload.daily.uv_index_max.first ?? 0,
                sunrise: Date(timeIntervalSince1970: sunriseEpoch),
                sunset: Date(timeIntervalSince1970: sunsetEpoch),
                daylightSeconds: payload.daily.daylight_duration.first ?? 0,
                timeZone: TimeZone(secondsFromGMT: payload.utc_offset_seconds) ?? .current
            )
        } catch {
            // Supplementary card — keep whatever we had.
        }
    }
}

// MARK: - Decoding

private struct OpenMeteoSun: Decodable {
    struct Current: Decodable {
        let uv_index: Double?
    }

    struct Daily: Decodable {
        let uv_index_max: [Double]
        let sunrise: [Double]
        let sunset: [Double]
        let daylight_duration: [Double]
    }

    let utc_offset_seconds: Int
    let current: Current
    let daily: Daily
}
