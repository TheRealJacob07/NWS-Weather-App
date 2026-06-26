import CoreLocation

enum RadarStationKind: String {
    case nexrad   // WSR-88D
    case tdwr     // Terminal Doppler Weather Radar
}

struct RadarSite: Equatable {
    let radarID: String
    let weatherOfficeID: String
    let name: String
    let latitude: Double
    let longitude: Double
    var kind: RadarStationKind = .nexrad
    var isOnline: Bool = true

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// TDWR sites publish different layer names than WSR-88D sites on
    /// opengeo.ncep.noaa.gov (e.g. tdfw_bref1 vs kfws_sr_bref).
    var reflectivityLayerName: String {
        let key = radarID.lowercased()
        return kind == .tdwr ? "\(key)_bref1" : "\(key)_sr_bref"
    }

    var velocityLayerName: String {
        let key = radarID.lowercased()
        return kind == .tdwr ? "\(key)_bvel" : "\(key)_sr_bvel"
    }
}

struct StormTrack: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let style: StormTrackStyle
}

enum StormTrackStyle: String {
    case motionTrack
    case warningArea
}

/// Active NWS alert polygon rendered on the radar map, colored by severity.
struct AlertPolygon: Identifiable {
    let id: String
    let event: String
    let severityKey: String   // "extreme" | "severe" | "moderate" | "minor" | "unknown"
    let headline: String?
    let endsText: String?
    let coordinates: [CLLocationCoordinate2D]

    /// Ray-casting point-in-polygon test for map tap hit-testing.
    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        guard coordinates.count > 2 else { return false }
        var inside = false
        var j = coordinates.count - 1
        for i in 0..<coordinates.count {
            let a = coordinates[i], b = coordinates[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
               point.longitude < (b.longitude - a.longitude)
                   * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

/// Contents of the liquid-glass inspector bubble shown when the user taps
/// the radar map.
struct RadarTapDetail: Equatable {
    let title: String
    let severityKey: String?
    let lines: [String]
}

/// NOAA RIDGE reflectivity color curve shared by the noise filter and the
/// tap inspector. 40 stops spanning -30 dBZ to +75 dBZ in 2.625 dBZ steps.
nonisolated enum ReflectivityScale {
    static let palette: [(UInt8, UInt8, UInt8)] = [
        (143, 133, 116), (147, 140, 94), (157, 153, 95), (171, 169, 118),
        (186, 186, 143), (201, 203, 167), (201, 204, 180), (185, 190, 180),
        (168, 175, 180), (155, 162, 180), (135, 145, 177), (112, 127, 171),
        (90, 111, 165), (75, 100, 161), (74, 114, 171), (87, 152, 194),
        (90, 183, 195), (85, 203, 173), (64, 214, 125), (32, 214, 57),
        (13, 193, 18), (11, 156, 16), (10, 125, 13), (9, 105, 10),
        (73, 128, 6), (191, 191, 2), (249, 214, 12), (239, 191, 34),
        (239, 178, 34), (249, 177, 11), (231, 4, 4), (186, 12, 12),
        (165, 11, 12), (173, 4, 4), (248, 219, 254), (234, 152, 253),
        (234, 116, 252), (247, 116, 254), (150, 0, 241), (110, 0, 221)
    ]

    /// Nearest-color dBZ estimate for an opaque radar pixel.
    static func dbz(red: Int, green: Int, blue: Int) -> Double {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, color) in palette.enumerated() {
            let dr = Double(red) - Double(color.0)
            let dg = Double(green) - Double(color.1)
            let db = Double(blue) - Double(color.2)
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return -30.0 + Double(bestIndex) * 2.625
    }

    static func intensityWord(forDBZ dbz: Double) -> String {
        switch dbz {
        case ..<20: return "Very light"
        case ..<35: return "Light rain"
        case ..<45: return "Moderate rain"
        case ..<55: return "Heavy rain"
        case ..<65: return "Intense — possible hail"
        default: return "Extreme — likely hail"
        }
    }
}

/// Marker placed at a warned storm's centroid showing the hazard type.
struct StormMarker: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let event: String
    let motionText: String?
}

struct RadarLayerConfiguration: Equatable {
    let serviceURL: String
    let layerName: String
    let sourceLabel: String
    /// When set, tile pixels mapping to reflectivity below this dBZ are
    /// made transparent (client-side noise filtering for raw site feeds).
    var minimumDBZ: Double? = nil
    /// Pre-rendered XYZ tile template ({z}/{x}/{y}). When set, tiles come
    /// from a CDN cache instead of per-tile WMS rendering — the difference
    /// between instant tiles and seconds-per-tile.
    var tileURLTemplate: String? = nil
}
