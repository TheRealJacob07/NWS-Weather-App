import MapKit
internal import Combine

@MainActor
final class LocationSearchService: ObservableObject {
    @Published private(set) var isSearching = false
    @Published private(set) var statusMessage: String?

    func search(query: String) async -> SavedLocation? {
        isSearching = true
        statusMessage = nil
        defer { isSearching = false }

        do {
            guard let request = MKGeocodingRequest(addressString: query) else {
                statusMessage = "No matching location was found."
                return nil
            }

            let mapItems = try await request.mapItems
            guard let mapItem = mapItems.first else {
                statusMessage = "No matching location was found."
                return nil
            }

            let coordinate = mapItem.location.coordinate
            let addressRepresentations = mapItem.addressRepresentations
            let name = mapItem.name
                ?? addressRepresentations?.cityWithContext(.full)
                ?? addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
                ?? query

            statusMessage = "Saved \(name)."
            return SavedLocation(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            statusMessage = "Unable to find that place right now."
            return nil
        }
    }
}
