import MapKit
import SwiftUI
internal import Combine

struct ContentView: View {
    @StateObject private var location = SimpleLocation()
    @StateObject private var weatherService = WeatherService()
    @StateObject private var locationSearchService = LocationSearchService()
    @State private var selectedPage: WeatherPage = .current
    @State private var activeSavedLocationID: UUID?
    @State private var savedLocations: [SavedLocation] = []
    @State private var hasLoadedSavedLocations = false
    @State private var locationSearchText = ""
    @State private var isShowingLocationSearch = false
    @AppStorage("saved_locations_data") private var savedLocationsData = ""

    var body: some View {
        ZStack {
            AtmosphericBackground(style: backgroundStyle)
                .ignoresSafeArea()

            if selectedPage == .radar {
                pageContent
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        locationBar
                        if selectedPage == .current {
                            heroCard
                        }
                        pageContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 120)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .preferredColorScheme(.dark)
        .task(id: weatherRequestID) {
            guard let coordinate = activeCoordinate else { return }
            await weatherService.loadWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        .task {
            guard !hasLoadedSavedLocations else { return }
            savedLocations = SavedLocation.decode(from: savedLocationsData)
            hasLoadedSavedLocations = true
            location.getLocation()
        }
        .onChange(of: savedLocations) { _, newValue in
            savedLocationsData = SavedLocation.encode(newValue)
        }
    }

    // MARK: - Location bar

    private var locationBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    Button("Use Device Location") {
                        activeSavedLocationID = nil
                        location.getLocation()
                    }

                    if !savedLocations.isEmpty { Divider() }

                    ForEach(savedLocations) { savedLocation in
                        Button(savedLocation.name) {
                            activeSavedLocationID = savedLocation.id
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeLocationName)
                                .font(.headline)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)

                Button {
                    activeSavedLocationID = nil
                    location.getLocation()
                } label: {
                    toolbarSymbol("location.viewfinder")
                }
                .buttonStyle(.glassProminent)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isShowingLocationSearch.toggle()
                    }
                } label: {
                    toolbarSymbol("magnifyingglass")
                }
                .buttonStyle(.glass)

                Button {
                    saveCurrentLocation()
                } label: {
                    toolbarSymbol("plus")
                }
                .buttonStyle(.glass)
                .disabled(location.coordinate == nil)
            }

            if isShowingLocationSearch {
                HStack(spacing: 12) {
                    TextField("Search city or town", text: $locationSearchText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        Task { await searchAndSaveLocation() }
                    } label: {
                        if locationSearchService.isSearching {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(width: 22, height: 22)
                        } else {
                            toolbarSymbol("arrow.right")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(
                        locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || locationSearchService.isSearching
                    )
                }

                if let searchStatus = locationSearchService.statusMessage {
                    Text(searchStatus)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.64))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let forecast = weatherService.forecast {
                        Text(forecast.periodName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Text(weatherService.forecast?.temperature ?? "--")
                        .font(.system(size: 84, weight: .thin, design: .rounded))
                }

                Spacer()

                Image(systemName: backgroundStyle.symbolName)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 8)
            }

            if let forecast = weatherService.forecast {
                VStack(alignment: .leading, spacing: 10) {
                    Text(forecast.shortForecast)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))

                    HStack(spacing: 20) {
                        Label("Wind \(forecast.wind)", systemImage: "wind")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))

                        Label(forecast.rain, systemImage: "drop.fill")
                            .font(.subheadline)
                            .foregroundStyle(.cyan.opacity(0.75))
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Page content

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .current:
            CurrentConditionsView(
                forecast: weatherService.forecast,
                observation: weatherService.currentObservation,
                hourlyPeriods: weatherService.hourlyPeriods
            )
        case .forecast:
            ForecastView(periods: weatherService.forecastPeriods)
        case .radar:
            RadarView(
                forecast: weatherService.forecast,
                coordinate: activeCoordinate,
                currentLocationCoordinate: location.coordinate,
                isLoading: weatherService.isLoading,
                locationStatus: activeLocationStatus
            )
        case .tools:
            ToolsView(
                forecast: weatherService.forecast,
                periods: weatherService.forecastPeriods,
                latitude: activeCoordinate?.latitude,
                longitude: activeCoordinate?.longitude,
                statusMessage: weatherService.statusMessage,
                activeLocationStatus: activeLocationStatus,
                savedLocationCount: savedLocations.count
            )
        }
    }

    // MARK: - Bottom toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            pageSelector
            locationButton
            refreshButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 28))
    }

    private var pageSelector: some View {
        HStack(spacing: 4) {
            ForEach(WeatherPage.allCases) { page in
                pageButton(for: page)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var locationButton: some View {
        Button {
            activeSavedLocationID = nil
            location.getLocation()
        } label: {
            toolbarSymbol("location.fill")
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var refreshButton: some View {
        Button {
            guard let coordinate = activeCoordinate else { return }
            Task {
                await weatherService.loadWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        } label: {
            if weatherService.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 22, height: 22)
            } else {
                toolbarSymbol("arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(activeCoordinate == nil || weatherService.isLoading)
    }

    @ViewBuilder
    private func pageButton(for page: WeatherPage) -> some View {
        let isSelected = selectedPage == page
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedPage = page
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: page.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(page.title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.16) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func toolbarSymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 22, height: 22)
    }

    // MARK: - Computed state

    private var activeLocationName: String {
        if let activeSavedLocation { return activeSavedLocation.name }
        if let forecast = weatherService.forecast { return "\(forecast.locationName), \(forecast.state)" }
        return "Current Location"
    }

    private var weatherRequestID: String {
        guard let coordinate = activeCoordinate else { return "no-location" }
        let sourceID = activeSavedLocationID?.uuidString ?? "device"
        return "\(sourceID)-\(coordinate.latitude),\(coordinate.longitude)"
    }

    private var activeSavedLocation: SavedLocation? {
        guard let activeSavedLocationID else { return nil }
        return savedLocations.first(where: { $0.id == activeSavedLocationID })
    }

    private var activeCoordinate: CLLocationCoordinate2D? {
        activeSavedLocation?.coordinate ?? location.coordinate
    }

    private var activeLocationStatus: String {
        if let activeSavedLocation { return "Viewing saved location \(activeSavedLocation.name)." }
        return location.statusMessage
    }

    private var backgroundStyle: WeatherBackgroundStyle {
        WeatherBackgroundStyle(forecastText: weatherService.forecast?.shortForecast)
    }

    // MARK: - Actions

    private func saveCurrentLocation() {
        guard let coordinate = location.coordinate else { return }

        let name: String
        if let forecast = weatherService.forecast {
            name = "\(forecast.locationName), \(forecast.state)"
        } else {
            name = "Saved Location \(savedLocations.count + 1)"
        }

        let savedLocation = SavedLocation(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        let isDuplicate = savedLocations.contains(where: {
            $0.name == savedLocation.name
            && abs($0.latitude - savedLocation.latitude) < 0.0001
            && abs($0.longitude - savedLocation.longitude) < 0.0001
        })
        guard !isDuplicate else { return }

        savedLocations.insert(savedLocation, at: 0)
        activeSavedLocationID = savedLocation.id
    }

    private func searchAndSaveLocation() async {
        let query = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let savedLocation = await locationSearchService.search(query: query) {
            if let existing = savedLocations.first(where: {
                abs($0.latitude - savedLocation.latitude) < 0.0001
                && abs($0.longitude - savedLocation.longitude) < 0.0001
            }) {
                activeSavedLocationID = existing.id
            } else {
                savedLocations.insert(savedLocation, at: 0)
                activeSavedLocationID = savedLocation.id
            }
            locationSearchText = ""
            isShowingLocationSearch = false
        }
    }
}

#Preview {
    ContentView()
}
