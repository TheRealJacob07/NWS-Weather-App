import CoreLocation
internal import Combine

class SimpleLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var coordinate: CLLocationCoordinate2D?
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var statusMessage = "Press the button to get your location."

    override init() {
        super.init()
        manager.delegate = self
    }

    func getLocation() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            statusMessage = "Requesting location permission..."
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            statusMessage = "Getting your location..."
            manager.requestLocation()
        } else {
            statusMessage = "Location access is unavailable. Enable permission in Settings."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            statusMessage = "Getting your location..."
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            statusMessage = "Location permission denied or restricted."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.first?.coordinate
        if let coordinate {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
            statusMessage = "Location loaded."
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        latitude = nil
        longitude = nil
        statusMessage = "Unable to get location: \(error.localizedDescription)"
    }
}
