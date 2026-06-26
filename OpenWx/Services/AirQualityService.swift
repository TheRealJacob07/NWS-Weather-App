import Foundation
import CoreLocation
internal import Combine

enum PollenLevel: String {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

struct PollenReading: Identifiable {
    let id: String      // "Tree", "Grass", "Ragweed"
    let level: PollenLevel
    let symbolName: String
}

struct AirQualitySnapshot {
    let aqi: Int
    let pm25: Double?
    let ozone: Double?

    var category: String {
        switch aqi {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for Sensitive Groups"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }

    /// 0…1 position along the AQI gauge (capped at 300).
    var gaugeRatio: Double {
        min(1.0, Double(aqi) / 300.0)
    }
}

/// Air quality via the free Open-Meteo air quality API (CAMS global model)
/// and pollen — measured where available (Europe), otherwise a transparent
/// seasonal estimate (the US has no free measured-pollen feed).
@MainActor
final class AirQualityService: ObservableObject {
    @Published private(set) var snapshot: AirQualitySnapshot?
    @Published private(set) var pollen: [PollenReading] = []
    @Published private(set) var pollenIsEstimated = false

    func load(coordinate: CLLocationCoordinate2D, precipChance: Int) async {
        let urlString = "https://air-quality-api.open-meteo.com/v1/air-quality"
            + "?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)"
            + "&current=us_aqi,pm2_5,ozone,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
            + "&timezone=auto"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await NetworkSessions.api.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
            let payload = try JSONDecoder().decode(OpenMeteoAirQuality.self, from: data)
            let current = payload.current

            if let aqi = current.us_aqi {
                snapshot = AirQualitySnapshot(
                    aqi: Int(aqi.rounded()),
                    pm25: current.pm2_5,
                    ozone: current.ozone
                )
            }

            if let measured = Self.measuredPollen(from: current) {
                pollen = measured
                pollenIsEstimated = false
            } else {
                pollen = Self.seasonalPollenEstimate(precipChance: precipChance)
                pollenIsEstimated = true
            }
        } catch {
            // Leave any previous data in place; these cards are supplementary.
        }
    }

    // MARK: - Pollen

    private static func measuredPollen(from current: OpenMeteoAirQuality.Current) -> [PollenReading]? {
        let tree = [current.alder_pollen, current.birch_pollen, current.olive_pollen]
            .compactMap { $0 }.max()
        let grass = current.grass_pollen
        let weed = [current.ragweed_pollen, current.mugwort_pollen]
            .compactMap { $0 }.max()

        // Open-Meteo returns null pollen outside Europe.
        guard tree != nil || grass != nil || weed != nil else { return nil }

        func level(_ value: Double?, moderate: Double, high: Double) -> PollenLevel {
            guard let value else { return .low }
            if value >= high { return .high }
            if value >= moderate { return .moderate }
            return .low
        }

        return [
            PollenReading(id: "Tree", level: level(tree, moderate: 90, high: 700), symbolName: "tree"),
            PollenReading(id: "Grass", level: level(grass, moderate: 20, high: 80), symbolName: "leaf"),
            PollenReading(id: "Ragweed", level: level(weed, moderate: 10, high: 50), symbolName: "allergens")
        ]
    }

    /// Calendar + forecast heuristic for regions without measured pollen:
    /// tree pollen peaks Feb–May, grass Apr–Aug, ragweed Aug–Oct; active
    /// rain suppresses airborne pollen a level.
    private static func seasonalPollenEstimate(precipChance: Int) -> [PollenReading] {
        let month = Calendar.current.component(.month, from: Date())

        func seasonLevel(peak: ClosedRange<Int>, shoulder: Set<Int>) -> PollenLevel {
            if peak.contains(month) { return .high }
            if shoulder.contains(month) { return .moderate }
            return .low
        }

        func damped(_ level: PollenLevel) -> PollenLevel {
            guard precipChance >= 60 else { return level }
            switch level {
            case .high: return .moderate
            case .moderate, .low: return .low
            }
        }

        return [
            PollenReading(id: "Tree", level: damped(seasonLevel(peak: 3...5, shoulder: [2, 6])), symbolName: "tree"),
            PollenReading(id: "Grass", level: damped(seasonLevel(peak: 5...7, shoulder: [4, 8])), symbolName: "leaf"),
            PollenReading(id: "Ragweed", level: damped(seasonLevel(peak: 8...10, shoulder: [7, 11])), symbolName: "allergens")
        ]
    }
}

// MARK: - Open-Meteo decoding

private struct OpenMeteoAirQuality: Decodable {
    struct Current: Decodable {
        let us_aqi: Double?
        let pm2_5: Double?
        let ozone: Double?
        let alder_pollen: Double?
        let birch_pollen: Double?
        let grass_pollen: Double?
        let mugwort_pollen: Double?
        let olive_pollen: Double?
        let ragweed_pollen: Double?
    }

    let current: Current
}
