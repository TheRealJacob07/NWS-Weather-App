import CoreLocation
import Foundation
internal import Combine

@MainActor
final class RadarSiteService: ObservableObject {
    @Published private(set) var nearestSite: RadarSite?
    @Published private(set) var sites: [RadarSite] = []
    @Published private(set) var isLoading = false

    private var cachedBaseSites: [RadarSite] = []
    private static let iso8601 = ISO8601DateFormatter()
    /// A radar is considered offline if no Level II data has been received recently.
    private static let onlineFreshnessWindow: TimeInterval = 30 * 60

    func loadNearestSite(for coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch the site list (cached for the session) and live station
            // statuses (refreshed every load) concurrently.
            async let statusTask = fetchStationStatuses()

            if cachedBaseSites.isEmpty {
                cachedBaseSites = try await fetchSites()
            }
            let statuses = await statusTask
            sites = cachedBaseSites.map { site in
                var site = site
                if let status = statuses[site.radarID] {
                    site.kind = status.kind
                    site.isOnline = status.isOnline
                } else if !statuses.isEmpty {
                    // Known to NWS WFS but absent from the status feed.
                    site.kind = Self.fallbackKind(for: site.radarID)
                    site.isOnline = false
                } else {
                    // Status feed unavailable — assume online so radar stays usable.
                    site.kind = Self.fallbackKind(for: site.radarID)
                }
                return site
            }

            let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let onlineSites = sites.filter(\.isOnline)
            nearestSite = (onlineSites.isEmpty ? sites : onlineSites).min {
                currentLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <
                currentLocation.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
        } catch {
            sites = []
            nearestSite = nil
        }
    }

    func nearbySites(for coordinate: CLLocationCoordinate2D, limit: Int) -> [RadarSite] {
        let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return sites
            .sorted {
                currentLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <
                currentLocation.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Station status (api.weather.gov)

    private struct StationStatus {
        let kind: RadarStationKind
        let isOnline: Bool
    }

    private func fetchStationStatuses() async -> [String: StationStatus] {
        guard let url = URL(string: "https://api.weather.gov/radar/stations") else { return [:] }
        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue("NWS Weather App (jacob@example.com)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let stations = try? JSONDecoder().decode(RadarStationsResponse.self, from: data) else {
            return [:]
        }

        var statuses: [String: StationStatus] = [:]
        for feature in stations.features {
            let props = feature.properties
            let kind: RadarStationKind = props.stationType == "TDWR" ? .tdwr : .nexrad

            var isOnline = false
            if let timestamp = props.latency?.levelTwoLastReceivedTime,
               let received = Self.iso8601.date(from: timestamp) {
                isOnline = Date().timeIntervalSince(received) < Self.onlineFreshnessWindow
            }
            statuses[props.id] = StationStatus(kind: kind, isOnline: isOnline)
        }
        return statuses
    }

    /// Used when the status feed is unavailable. All TDWR IDs start with "T";
    /// the only WSR-88D that also does is TJUA (San Juan).
    private static func fallbackKind(for radarID: String) -> RadarStationKind {
        radarID.hasPrefix("T") && radarID != "TJUA" ? .tdwr : .nexrad
    }

    // MARK: - Site list (opengeo WFS)

    private func fetchSites() async throws -> [RadarSite] {
        let url = URL(string: "https://opengeo.ncep.noaa.gov/geoserver/nws/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=nws:radar_sites")!
        var request = URLRequest(url: url)
        request.setValue("NWS Weather App (jacob@example.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let xml = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseRadarSites(from: xml)
    }

    private func parseRadarSites(from xml: String) -> [RadarSite] {
        xml.components(separatedBy: "<gml:featureMember>")
            .dropFirst()
            .compactMap { member in
                guard
                    let radarID = xmlValue(in: member, tag: "nws:rda_id"),
                    let weatherOfficeID = xmlValue(in: member, tag: "nws:wfo_id"),
                    let name = xmlValue(in: member, tag: "nws:name"),
                    let latStr = xmlValue(in: member, tag: "nws:lat"),
                    let lonStr = xmlValue(in: member, tag: "nws:lon"),
                    let latitude = Double(latStr),
                    let longitude = Double(lonStr)
                else { return nil }
                return RadarSite(
                    radarID: radarID,
                    weatherOfficeID: weatherOfficeID,
                    name: name,
                    latitude: latitude,
                    longitude: longitude
                )
            }
    }

    // Simple string-based tag extraction — faster than regex for fixed XML structure
    private func xmlValue(in text: String, tag: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let startRange = text.range(of: open),
              let endRange = text.range(of: close, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
    }
}

// MARK: - api.weather.gov radar station types

private struct RadarStationsResponse: Decodable {
    let features: [RadarStationFeature]
}

private struct RadarStationFeature: Decodable {
    let properties: RadarStationProperties
}

private struct RadarStationProperties: Decodable {
    let id: String
    let stationType: String?
    let latency: RadarStationLatency?
}

private struct RadarStationLatency: Decodable {
    let levelTwoLastReceivedTime: String?
}
