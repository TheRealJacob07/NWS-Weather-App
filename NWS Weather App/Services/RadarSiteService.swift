import CoreLocation
internal import Combine

@MainActor
final class RadarSiteService: ObservableObject {
    @Published private(set) var nearestSite: RadarSite?
    @Published private(set) var sites: [RadarSite] = []
    @Published private(set) var isLoading = false

    private var cachedSites: [RadarSite] = []

    func loadNearestSite(for coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }

        do {
            if cachedSites.isEmpty {
                cachedSites = try await fetchSites()
            }
            sites = cachedSites

            let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            nearestSite = cachedSites.min {
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
