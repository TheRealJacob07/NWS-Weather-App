import MapKit
internal import Combine

/// Live city autocomplete (MKLocalSearchCompleter) plus resolution of a
/// chosen completion into a saved location.
@MainActor
final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion
    }

    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var statusMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Cities and towns only — keeps street addresses out of the list.
        completer.addressFilter = MKAddressFilter(including: .locality)
    }

    func updateQuery(_ text: String) {
        statusMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            completer.queryFragment = ""
        } else {
            completer.queryFragment = trimmed
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.map {
            Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }

    // MARK: - Resolution

    /// Resolves an autocomplete suggestion to coordinates.
    func resolve(_ suggestion: Suggestion) async -> SavedLocation? {
        isSearching = true
        defer { isSearching = false }

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        guard let response = try? await search.start(),
              let mapItem = response.mapItems.first else {
            statusMessage = "Unable to find that place right now."
            return nil
        }

        let coordinate = mapItem.location.coordinate
        return SavedLocation(
            name: suggestion.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    /// Free-text fallback for keyboard submit without picking a suggestion.
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

            return SavedLocation(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            statusMessage = "Unable to find that place right now."
            return nil
        }
    }
}
