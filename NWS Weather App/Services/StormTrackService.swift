import CoreLocation
import Foundation
internal import Combine

@MainActor
final class StormTrackService: ObservableObject {
    @Published private(set) var tracks: [StormTrack] = []

    // Compiled once at class load time rather than inside the hot path
    private static let motionPattern = try? NSRegularExpression(
        pattern: #"MOVING\s+([A-Z]+)\s+AT\s+(\d+)\s+(MPH|KTS)"#
    )

    func loadTracks(for coordinate: CLLocationCoordinate2D) async {
        do {
            tracks = try await fetchTracks(for: coordinate)
        } catch {
            tracks = []
        }
    }

    private func fetchTracks(for coordinate: CLLocationCoordinate2D) async throws -> [StormTrack] {
        let url = URL(string: "https://api.weather.gov/alerts/active?point=\(coordinate.latitude),\(coordinate.longitude)")!
        var request = URLRequest(url: url)
        request.setValue("NWS Weather App (jacob@example.com)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            return []
        }

        let payload = try JSONDecoder().decode(AlertCollection.self, from: data)
        return payload.features.flatMap(makeTracks(from:))
    }

    private func makeTracks(from feature: AlertFeature) -> [StormTrack] {
        let event = feature.properties.event.lowercased()
        let isStormEvent = event.contains("thunderstorm")
            || event.contains("tornado")
            || event.contains("marine")
            || event.contains("snow squall")
        guard isStormEvent else { return [] }

        let polygonCoordinates = feature.geometry.primaryRing
        guard polygonCoordinates.count > 1 else { return [] }

        var tracks: [StormTrack] = [StormTrack(coordinates: polygonCoordinates, style: .warningArea)]
        if let motionTrack = motionTrack(from: feature.properties.description, polygonCoordinates: polygonCoordinates) {
            tracks.append(motionTrack)
        }
        return tracks
    }

    private func motionTrack(from description: String, polygonCoordinates: [CLLocationCoordinate2D]) -> StormTrack? {
        guard let expression = StormTrackService.motionPattern else { return nil }
        let upper = description.uppercased()
        let range = NSRange(upper.startIndex..., in: upper)
        guard let match = expression.firstMatch(in: upper, range: range),
              let dirRange = Range(match.range(at: 1), in: upper),
              let speedRange = Range(match.range(at: 2), in: upper),
              let unitRange = Range(match.range(at: 3), in: upper) else {
            return nil
        }

        let direction = String(upper[dirRange])
        let speedText = String(upper[speedRange])
        let unit = String(upper[unitRange])
        guard let bearing = bearing(for: direction), let speedValue = Double(speedText) else { return nil }

        let mps = unit == "KTS" ? speedValue * 0.514444 : speedValue * 0.44704
        let center = centroid(for: polygonCoordinates)
        let projected = project(from: center, distanceMeters: mps * 60 * 30, bearingDegrees: bearing)
        return StormTrack(coordinates: [center, projected], style: .motionTrack)
    }

    private func centroid(for coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count),
            longitude: coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        )
    }

    private func project(
        from coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let b = bearingDegrees * .pi / 180
        let lat = coordinate.latitude * .pi / 180
        let lon = coordinate.longitude * .pi / 180
        let d = distanceMeters / R

        let projLat = asin(sin(lat) * cos(d) + cos(lat) * sin(d) * cos(b))
        let projLon = lon + atan2(sin(b) * sin(d) * cos(lat), cos(d) - sin(lat) * sin(projLat))

        return CLLocationCoordinate2D(
            latitude: projLat * 180 / .pi,
            longitude: projLon * 180 / .pi
        )
    }

    private func bearing(for direction: String) -> Double? {
        switch direction {
        case "N": return 0; case "NNE": return 22.5; case "NE": return 45
        case "ENE": return 67.5; case "E": return 90; case "ESE": return 112.5
        case "SE": return 135; case "SSE": return 157.5; case "S": return 180
        case "SSW": return 202.5; case "SW": return 225; case "WSW": return 247.5
        case "W": return 270; case "WNW": return 292.5; case "NW": return 315
        case "NNW": return 337.5; default: return nil
        }
    }
}

// MARK: - Private NWS alert decoding types

private struct AlertCollection: Decodable {
    let features: [AlertFeature]
}

private struct AlertFeature: Decodable {
    let properties: AlertProperties
    let geometry: AlertGeometry
}

private struct AlertProperties: Decodable {
    let event: String
    let description: String
}

private struct AlertGeometry: Decodable {
    let coordinates: [[[Double]]]

    var primaryRing: [CLLocationCoordinate2D] {
        guard let ring = coordinates.first else { return [] }
        return ring.compactMap { point in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
    }
}
