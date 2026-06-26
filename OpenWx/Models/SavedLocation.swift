import CoreLocation

struct SavedLocation: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinateLine: String {
        let lat = latitude.formatted(.number.precision(.fractionLength(3)))
        let lon = longitude.formatted(.number.precision(.fractionLength(3)))
        return "\(lat), \(lon)"
    }

    static func decode(from storage: String) -> [SavedLocation] {
        guard !storage.isEmpty,
              let data = storage.data(using: .utf8),
              let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return []
        }
        return locations
    }

    static func encode(_ locations: [SavedLocation]) -> String {
        guard let data = try? JSONEncoder().encode(locations),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
