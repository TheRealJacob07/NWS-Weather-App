import CoreLocation
internal import Combine

@MainActor
final class SimpleLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var coordinate: CLLocationCoordinate2D?
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var statusMessage = "Press the button to get your location."

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func getLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            coordinate = nil
            latitude = nil
            longitude = nil
            statusMessage = "Location Services are turned off. Enable them in Settings."
            return
        }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            statusMessage = "Requesting location permission..."
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            requestLocation()
        } else {
            statusMessage = "Location access is unavailable. Enable permission in Settings."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            requestLocation()
        } else if status == .denied || status == .restricted {
            coordinate = nil
            latitude = nil
            longitude = nil
            statusMessage = "Location permission denied or restricted."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        update(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        coordinate = nil
        latitude = nil
        longitude = nil
        statusMessage = "Unable to get location: \(error.localizedDescription)"
    }

    private func requestLocation() {
        statusMessage = "Getting your location..."
        if let existingLocation = manager.location {
            update(with: existingLocation)
            return
        }

        manager.requestLocation()
    }

    private func update(with location: CLLocation) {
        coordinate = location.coordinate
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        statusMessage = "Location loaded."
    }
}
