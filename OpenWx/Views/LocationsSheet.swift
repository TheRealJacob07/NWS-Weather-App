import SwiftUI

/// Apple Weather-style location list: search to add cities,
/// tap to switch, swipe to delete.
struct LocationsSheet: View {
    @Binding var savedLocations: [SavedLocation]
    @Binding var activeSavedLocationID: UUID?
    let deviceLocationName: String
    let onUseDeviceLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = LocationSearchService()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if !searchService.suggestions.isEmpty && !searchText.isEmpty {
                    Section {
                        ForEach(searchService.suggestions) { suggestion in
                            Button {
                                Task { await add(suggestion) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.cyan.opacity(0.8))
                                        .frame(width: 26)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.white)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.55))
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(rowBackground)
                        }
                    } header: {
                        Text("Suggestions")
                    }
                }

                Section {
                    Button {
                        onUseDeviceLocation()
                        dismiss()
                    } label: {
                        locationRow(
                            title: "My Location",
                            subtitle: deviceLocationName,
                            icon: "location.fill",
                            isActive: activeSavedLocationID == nil
                        )
                    }
                    .listRowBackground(rowBackground)
                }

                if !savedLocations.isEmpty {
                    Section {
                        ForEach(savedLocations) { location in
                            Button {
                                activeSavedLocationID = location.id
                                dismiss()
                            } label: {
                                locationRow(
                                    title: location.name,
                                    subtitle: String(
                                        format: "%.2f°, %.2f°",
                                        location.latitude,
                                        location.longitude
                                    ),
                                    icon: "mappin.circle.fill",
                                    isActive: activeSavedLocationID == location.id
                                )
                            }
                            .listRowBackground(rowBackground)
                        }
                        .onDelete(perform: deleteLocations)
                    } header: {
                        Text("Saved Locations")
                    }
                }

                if let status = searchService.statusMessage {
                    Section {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                            .listRowBackground(rowBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search for a city or town")
            .onChange(of: searchText) { _, newValue in
                searchService.updateQuery(newValue)
            }
            .onSubmit(of: .search) {
                Task { await searchAndAddLocation() }
            }
            .overlay {
                if searchService.isSearching {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var rowBackground: some View {
        Color.white.opacity(0.06)
    }

    private func locationRow(title: String, subtitle: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.cyan)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteLocations(at offsets: IndexSet) {
        let removedIDs = offsets.map { savedLocations[$0].id }
        savedLocations.remove(atOffsets: offsets)
        if let activeSavedLocationID, removedIDs.contains(activeSavedLocationID) {
            self.activeSavedLocationID = nil
            onUseDeviceLocation()
        }
    }

    private func add(_ suggestion: LocationSearchService.Suggestion) async {
        if let result = await searchService.resolve(suggestion) {
            save(result)
        }
    }

    private func searchAndAddLocation() async {
        // Prefer the top autocomplete suggestion on keyboard submit.
        if let first = searchService.suggestions.first {
            await add(first)
            return
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let result = await searchService.search(query: query) {
            save(result)
        }
    }

    private func save(_ result: SavedLocation) {
        if let existing = savedLocations.first(where: {
            abs($0.latitude - result.latitude) < 0.0001
            && abs($0.longitude - result.longitude) < 0.0001
        }) {
            activeSavedLocationID = existing.id
        } else {
            savedLocations.insert(result, at: 0)
            activeSavedLocationID = result.id
        }
        searchText = ""
        searchService.updateQuery("")
        dismiss()
    }
}
