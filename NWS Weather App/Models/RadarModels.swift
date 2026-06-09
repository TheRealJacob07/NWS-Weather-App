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

struct RadarLayerConfiguration: Equatable {
    let serviceURL: String
    let layerName: String
    let sourceLabel: String
    /// When set, tile pixels mapping to reflectivity below this dBZ are
    /// made transparent (client-side noise filtering for raw site feeds).
    var minimumDBZ: Double? = nil
}
