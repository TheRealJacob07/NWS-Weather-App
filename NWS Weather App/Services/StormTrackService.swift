import CoreLocation
import Foundation
internal import Combine

@MainActor
final class StormTrackService: ObservableObject {
    @Published private(set) var tracks: [StormTrack] = []
    @Published private(set) var alertPolygons: [AlertPolygon] = []
    @Published private(set) var stormMarkers: [StormMarker] = []

    // Compiled once at class load time rather than inside the hot path.
    // The direction group allows multi-word / hyphenated headings such as
    // "EAST-NORTHEAST" or "NORTH NORTHEAST" (older "MOVING E AT" forms still
    // match too).
    private static let motionPattern = try? NSRegularExpression(
        pattern: #"MOVING\s+([A-Z][A-Z\s\-]*?)\s+AT\s+(\d+)\s+(MPH|KTS|KT)"#
    )

    // Structured NWS storm-motion vector: "<ISO time>...storm...<bbb>DEG...<sss>KT".
    private static let motionVectorPattern = try? NSRegularExpression(
        pattern: #"(\d{1,3})\s*DEG.*?(\d{1,3})\s*KT"#
    )

    func loadTracks(for coordinate: CLLocationCoordinate2D) async {
        do {
            let result = try await fetchAlertOverlays(for: coordinate)
            tracks = result.tracks
            alertPolygons = result.polygons
            stormMarkers = result.markers
        } catch {
            tracks = []
            alertPolygons = []
            stormMarkers = []
        }
    }

    private func fetchAlertOverlays(
        for coordinate: CLLocationCoordinate2D
    ) async throws -> (tracks: [StormTrack], polygons: [AlertPolygon], markers: [StormMarker]) {
        // Two feeds, fetched concurrently:
        //  • point: every alert affecting the user's location (any severity),
        //    with zone-shape fallback so county-based alerts still draw.
        //  • national: all Severe/Extreme alerts countrywide, so warned
        //    storms are visible wherever the user pans — like dedicated
        //    radar apps. (Note: /alerts/active rejects a `limit` param.)
        let lat = coordinate.latitude, lon = coordinate.longitude
        let pointURL = URL(string: "https://api.weather.gov/alerts/active?status=actual&message_type=alert&point=\(lat),\(lon)")!
        let nationalURL = URL(string: "https://api.weather.gov/alerts/active?status=actual&message_type=alert&severity=Extreme,Severe")!

        async let pointFeatures = fetchFeatures(from: pointURL)
        async let nationalFeatures = fetchFeatures(from: nationalURL)
        let (point, national) = try await (pointFeatures, nationalFeatures)

        // Merge, point alerts first (they keep zone-fallback priority).
        var seen = Set<String>()
        var features: [AlertFeature] = []
        for feature in point + national where seen.insert(feature.id).inserted {
            features.append(feature)
        }

        var tracks: [StormTrack] = []
        var polygons: [AlertPolygon] = []
        var markers: [StormMarker] = []
        var zoneFetchBudget = 8

        for feature in features {
            var rings = feature.geometry?.rings ?? []

            // Zone/county-based alerts (watches, advisories, flood warnings)
            // carry no inline polygon — pull the affected zone shapes so the
            // Alerts layer still draws them.
            if rings.isEmpty, zoneFetchBudget > 0,
               let zones = feature.properties.affectedZones {
                for zoneURL in zones.prefix(3) where zoneFetchBudget > 0 {
                    zoneFetchBudget -= 1
                    if let zoneRings = await zoneGeometry(for: zoneURL) {
                        rings.append(contentsOf: zoneRings)
                    }
                }
            }

            for (ringIndex, ring) in rings.enumerated() where ring.count > 2 {
                polygons.append(
                    AlertPolygon(
                        id: "\(feature.id)-\(ringIndex)",
                        event: feature.properties.event,
                        severityKey: feature.properties.severity?.lowercased() ?? "unknown",
                        headline: feature.properties.headline,
                        endsText: Self.endsText(from: feature.properties),
                        coordinates: ring
                    )
                )
            }

            guard isStormEvent(feature.properties.event),
                  let ring = feature.geometry?.rings.first, ring.count > 2 else { continue }

            tracks.append(StormTrack(coordinates: ring, style: .warningArea))

            let center = centroid(for: ring)
            // Prefer the structured storm-motion vector NWS ships in the
            // alert parameters; fall back to scraping the prose description.
            let motion = motionVector(from: feature.properties.parameters)
                ?? motionDescription(from: feature.properties.description ?? "")
            markers.append(
                StormMarker(
                    id: feature.id,
                    coordinate: center,
                    event: feature.properties.event,
                    motionText: motion?.text
                )
            )

            if let motion {
                tracks.append(contentsOf: motionTracks(
                    from: center,
                    bearing: motion.bearing,
                    metersPerSecond: motion.metersPerSecond
                ))
            }
        }

        return (tracks, polygons, markers)
    }

    /// Lossy decoding: one alert with unexpected geometry must never take
    /// down every overlay on the map.
    private func fetchFeatures(from url: URL) async throws -> [AlertFeature] {
        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await NetworkSessions.api.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            return []
        }

        let payload = try JSONDecoder().decode(AlertCollection.self, from: data)
        return payload.features.compactMap(\.value)
    }

    // MARK: - Zone geometry fallback

    /// Zone shapes never change — cache them for the app's lifetime.
    private var zoneGeometryCache: [String: [[CLLocationCoordinate2D]]] = [:]

    private func zoneGeometry(for zoneURL: String) async -> [[CLLocationCoordinate2D]]? {
        if let cached = zoneGeometryCache[zoneURL] { return cached }
        guard let url = URL(string: zoneURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await NetworkSessions.api.data(for: request),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let zone = try? JSONDecoder().decode(ZoneResponse.self, from: data),
              let rings = zone.geometry?.rings, !rings.isEmpty else {
            return nil
        }

        // Zone boundaries can run to thousands of vertices; thin them so the
        // map stays responsive.
        let simplified = rings.map { ring -> [CLLocationCoordinate2D] in
            guard ring.count > 300 else { return ring }
            let stride = ring.count / 300 + 1
            var thinned = ring.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
            if let first = thinned.first { thinned.append(first) }
            return thinned
        }

        zoneGeometryCache[zoneURL] = simplified
        return simplified
    }

    private static let endsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    private static func endsText(from properties: AlertProperties) -> String? {
        guard let raw = properties.ends ?? properties.expires,
              let date = isoFormatter.date(from: raw) else { return nil }
        return "Until \(endsFormatter.string(from: date))"
    }

    private func isStormEvent(_ event: String) -> Bool {
        let lowered = event.lowercased()
        return lowered.contains("thunderstorm")
            || lowered.contains("tornado")
            || lowered.contains("marine")
            || lowered.contains("snow squall")
    }

    // MARK: - Storm motion

    private struct Motion {
        let bearing: Double
        let metersPerSecond: Double
        let text: String
    }

    /// Parses NWS's machine-readable storm-motion vector out of the alert
    /// `parameters` dictionary (key `eventMotionDescription`). Its degrees
    /// are the bearing the storm is moving *from* (meteorological "from"
    /// convention), so the travel heading is that value plus 180°.
    private func motionVector(from parameters: MotionParameters?) -> Motion? {
        guard let raw = parameters?.eventMotionDescription?.first,
              let expression = StormTrackService.motionVectorPattern else { return nil }
        let upper = raw.uppercased()
        let range = NSRange(upper.startIndex..., in: upper)
        guard let match = expression.firstMatch(in: upper, range: range),
              let degRange = Range(match.range(at: 1), in: upper),
              let ktRange = Range(match.range(at: 2), in: upper),
              let fromBearing = Double(upper[degRange]),
              let knots = Double(upper[ktRange]) else {
            return nil
        }

        let heading = (fromBearing + 180).truncatingRemainder(dividingBy: 360)
        let mph = knots * 1.15078
        return Motion(
            bearing: heading,
            metersPerSecond: knots * 0.514444,
            text: "Moving \(compassWord(forBearing: heading)) at \(Int(mph.rounded())) mph"
        )
    }

    private func motionDescription(from description: String) -> Motion? {
        guard let expression = StormTrackService.motionPattern else { return nil }
        let upper = description.uppercased()
        let range = NSRange(upper.startIndex..., in: upper)
        guard let match = expression.firstMatch(in: upper, range: range),
              let dirRange = Range(match.range(at: 1), in: upper),
              let speedRange = Range(match.range(at: 2), in: upper),
              let unitRange = Range(match.range(at: 3), in: upper) else {
            return nil
        }

        let direction = String(upper[dirRange]).trimmingCharacters(in: .whitespaces)
        let speedText = String(upper[speedRange])
        let unit = String(upper[unitRange])
        guard let bearing = bearing(for: direction), let speedValue = Double(speedText) else { return nil }

        let isKnots = unit.hasPrefix("KT")
        let mps = isKnots ? speedValue * 0.514444 : speedValue * 0.44704
        let mph = isKnots ? speedValue * 1.15078 : speedValue
        return Motion(
            bearing: bearing,
            metersPerSecond: mps,
            text: "Moving \(direction.capitalized) at \(Int(mph.rounded())) mph"
        )
    }

    /// Builds the projected motion line plus a small arrowhead at its tip so
    /// the direction of travel is obvious at a glance.
    private func motionTracks(
        from center: CLLocationCoordinate2D,
        bearing: Double,
        metersPerSecond: Double
    ) -> [StormTrack] {
        let distance = metersPerSecond * 60 * 30 // 30-minute projection
        let tip = project(from: center, distanceMeters: distance, bearingDegrees: bearing)
        var tracks = [StormTrack(coordinates: [center, tip], style: .motionTrack)]

        let headLength = max(2_000, distance * 0.18)
        let left = project(from: tip, distanceMeters: headLength, bearingDegrees: bearing + 150)
        let right = project(from: tip, distanceMeters: headLength, bearingDegrees: bearing - 150)
        tracks.append(StormTrack(coordinates: [left, tip, right], style: .motionTrack))
        return tracks
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

    /// Accepts NWS abbreviations ("NE", "ENE") and the spelled-out forms used
    /// in warning prose ("NORTHEAST", "EAST-NORTHEAST", "NORTH NORTHEAST").
    private func bearing(for direction: String) -> Double? {
        let key = direction
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch key {
        case "N", "NORTH": return 0
        case "NNE", "NORTHNORTHEAST": return 22.5
        case "NE", "NORTHEAST": return 45
        case "ENE", "EASTNORTHEAST": return 67.5
        case "E", "EAST": return 90
        case "ESE", "EASTSOUTHEAST": return 112.5
        case "SE", "SOUTHEAST": return 135
        case "SSE", "SOUTHSOUTHEAST": return 157.5
        case "S", "SOUTH": return 180
        case "SSW", "SOUTHSOUTHWEST": return 202.5
        case "SW", "SOUTHWEST": return 225
        case "WSW", "WESTSOUTHWEST": return 247.5
        case "W", "WEST": return 270
        case "WNW", "WESTNORTHWEST": return 292.5
        case "NW", "NORTHWEST": return 315
        case "NNW", "NORTHNORTHWEST": return 337.5
        default: return nil
        }
    }

    private static let compassPoints = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
    ]

    private func compassWord(forBearing bearing: Double) -> String {
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % 16
        return Self.compassPoints[index]
    }
}

// MARK: - Private NWS alert decoding types

/// Wraps a decodable so a single malformed element can't fail the whole
/// collection — the bad element just becomes nil.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

private struct AlertCollection: Decodable {
    let features: [Lossy<AlertFeature>]
}

private struct AlertFeature: Decodable {
    let id: String
    let properties: AlertProperties
    let geometry: GeoJSONGeometry?
}

private struct AlertProperties: Decodable {
    let event: String
    let severity: String?
    let headline: String?
    let description: String?
    let ends: String?
    let expires: String?
    let affectedZones: [String]?
    /// NWS ships extra fields here; we only need the structured storm-motion
    /// vector. Scoping the type to one key keeps an unexpected `parameters`
    /// shape from failing the whole alert decode.
    let parameters: MotionParameters?
}

private struct MotionParameters: Decodable {
    let eventMotionDescription: [String]?
}

private struct ZoneResponse: Decodable {
    let geometry: GeoJSONGeometry?
}

/// Tolerant GeoJSON geometry: handles Polygon and MultiPolygon, yielding
/// the outer ring(s). Anything else decodes to empty rather than throwing.
private struct GeoJSONGeometry: Decodable {
    let rings: [[CLLocationCoordinate2D]]

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? ""

        switch type {
        case "Polygon":
            let raw = (try? container.decode([[[Double]]].self, forKey: .coordinates)) ?? []
            rings = raw.first.map { [Self.ring(from: $0)] } ?? []
        case "MultiPolygon":
            let raw = (try? container.decode([[[[Double]]]].self, forKey: .coordinates)) ?? []
            rings = raw.compactMap { polygon in
                polygon.first.map(Self.ring(from:))
            }
        default:
            rings = []
        }
    }

    private static func ring(from points: [[Double]]) -> [CLLocationCoordinate2D] {
        points.compactMap { point in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
    }
}
