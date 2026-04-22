import CoreLocation

struct RadarSite: Equatable {
    let radarID: String
    let weatherOfficeID: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
}
