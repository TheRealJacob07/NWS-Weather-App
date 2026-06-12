import MapKit
import SwiftUI
internal import Combine

struct ContentView: View {
    @StateObject private var location = SimpleLocation()
    @StateObject private var weatherService = WeatherService()
    @StateObject private var intelligence = WeatherIntelligenceService()
    @StateObject private var airQuality = AirQualityService()
    @StateObject private var sun = SunService()
    @State private var activeSavedLocationID: UUID?
    @State private var savedLocations: [SavedLocation] = []
    @State private var hasLoadedSavedLocations = false
    @State private var isShowingLocations = false
    @State private var isShowingRadar = false
    @State private var isShowingTools = false
    @State private var isShowingChat = false
    @State private var selectedAlert: WeatherAlertSummary?
    @AppStorage("saved_locations_data") private var savedLocationsData = ""

    var body: some View {
        ZStack {
            AtmosphericBackground(style: backgroundStyle)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    hero
                        .padding(.top, 44)
                        .padding(.bottom, 26)

                    if weatherService.forecast == nil {
                        statusCard
                    }

                    ForEach(weatherService.alerts) { alert in
                        Button {
                            selectedAlert = alert
                        } label: {
                            AlertBanner(alert: alert)
                        }
                        .buttonStyle(.plain)
                    }

                    if weatherService.forecast != nil {
                        AISummaryCard(intelligence: intelligence) {
                            isShowingChat = true
                        }
                    }

                    if !weatherService.hourlyPeriods.isEmpty {
                        HourlyForecastCard(
                            periods: weatherService.hourlyPeriods,
                            summaryText: weatherService.forecast?.shortForecast
                        )
                    }

                    if !weatherService.dailyForecasts.isEmpty {
                        DailyForecastCard(days: weatherService.dailyForecasts)
                    }

                    if let observation = weatherService.currentObservation {
                        ConditionTilesGrid(
                            forecast: weatherService.forecast,
                            observation: observation
                        )
                    }

                    if let forecast = weatherService.forecast, !forecast.detailedForecast.isEmpty {
                        detailsCard(for: forecast)
                    }

                    if let sunSnapshot = sun.snapshot {
                        UVIndexCard(snapshot: sunSnapshot)
                        SunExposureCard(snapshot: sunSnapshot)
                    }

                    if let aqSnapshot = airQuality.snapshot {
                        AirQualityCard(snapshot: aqSnapshot)
                    }

                    if !airQuality.pollen.isEmpty {
                        AllergenCard(
                            readings: airQuality.pollen,
                            isEstimated: airQuality.pollenIsEstimated
                        )
                    }

                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .refreshable { await refresh() }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingLocations) {
            LocationsSheet(
                savedLocations: $savedLocations,
                activeSavedLocationID: $activeSavedLocationID,
                deviceLocationName: deviceLocationName,
                onUseDeviceLocation: {
                    activeSavedLocationID = nil
                    location.getLocation()
                }
            )
        }
        .sheet(isPresented: $isShowingTools) {
            ToolsView(
                statusMessage: weatherService.statusMessage,
                activeLocationStatus: activeLocationStatus,
                savedLocationCount: savedLocations.count
            )
        }
        .sheet(item: $selectedAlert) { alert in
            AlertDetailSheet(alert: alert)
        }
        .sheet(isPresented: $isShowingChat) {
            WeatherChatSheet(
                intelligence: intelligence,
                locationName: activeLocationName
            )
        }
        .fullScreenCover(isPresented: $isShowingRadar) {
            RadarView(
                forecast: weatherService.forecast,
                coordinate: activeCoordinate,
                currentLocationCoordinate: location.coordinate,
                locationStatus: activeLocationStatus
            )
        }
        .task(id: weatherRequestID) {
            guard let coordinate = activeCoordinate else { return }
            await weatherService.loadWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
            async let environmentTask: Void = refreshEnvironment()
            async let intelligenceTask: Void = refreshIntelligence()
            _ = await (environmentTask, intelligenceTask)
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

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 2) {
            if activeSavedLocationID == nil {
                Label("My Location", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .labelStyle(.titleAndIcon)
            }

            Text(activeLocationName)
                .font(.system(size: 32, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Observed station temperature (what NWS calls "current
            // conditions") — the forecast period temp is today's high/low,
            // not the temperature right now.
            Text(currentTemperatureText)
                .font(.system(size: 100, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .padding(.leading, 20) // optically center, offsetting the degree sign
                .contentTransition(.numericText())

            if let forecast = weatherService.forecast {
                Text(forecast.shortForecast)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                Text(forecast.highLowText)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
            } else if weatherService.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
    }

    // MARK: - Cards

    private var statusCard: some View {
        WeatherCard(icon: "info.circle", title: "Status") {
            VStack(alignment: .leading, spacing: 12) {
                Text(weatherService.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                if !weatherService.isLoading {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .disabled(activeCoordinate == nil)
                }
            }
            .padding(16)
        }
    }

    private func detailsCard(for forecast: ForecastSummary) -> some View {
        WeatherCard(icon: "text.alignleft", title: forecast.periodName) {
            Text(forecast.detailedForecast)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
                .padding(16)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Data provided by the National Weather Service")
            if let observation = weatherService.currentObservation {
                Text("Observed at \(observation.lastUpdate)")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    isShowingRadar = true
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)

                Button {
                    isShowingLocations = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: activeSavedLocationID == nil ? "location.fill" : "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        Text(activeLocationName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)

                Menu {
                    Button {
                        isShowingChat = true
                    } label: {
                        Label("Ask Weather AI", systemImage: "sparkles")
                    }

                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        activeSavedLocationID = nil
                        location.getLocation()
                    } label: {
                        Label("Use Current Location", systemImage: "location")
                    }

                    Button {
                        isShowingTools = true
                    } label: {
                        Label("NWS Resources", systemImage: "square.grid.2x2")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .contentShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }

    // MARK: - Computed state

    private var currentTemperatureText: String {
        if let observed = weatherService.currentObservation?.temperatureValue {
            return "\(observed)°"
        }
        return weatherService.forecast?.temperatureText ?? "--"
    }

    private var activeLocationName: String {
        if let activeSavedLocation { return activeSavedLocation.name }
        if let forecast = weatherService.forecast { return forecast.locationName }
        return "Current Location"
    }

    private var deviceLocationName: String {
        if activeSavedLocationID == nil, let forecast = weatherService.forecast {
            return "\(forecast.locationName), \(forecast.state)"
        }
        return location.statusMessage
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
        WeatherBackgroundStyle(
            forecastText: weatherService.forecast?.shortForecast,
            isDaytime: weatherService.forecast?.isDaytime ?? true
        )
    }

    // MARK: - Actions

    private func refresh() async {
        guard let coordinate = activeCoordinate else { return }
        await weatherService.loadWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
        async let environmentTask: Void = refreshEnvironment()
        async let intelligenceTask: Void = refreshIntelligence()
        _ = await (environmentTask, intelligenceTask)
    }

    private func refreshEnvironment() async {
        guard let coordinate = activeCoordinate else { return }
        async let airTask: Void = airQuality.load(
            coordinate: coordinate,
            precipChance: weatherService.forecast?.precipChance ?? 0
        )
        async let sunTask: Void = sun.load(coordinate: coordinate)
        _ = await (airTask, sunTask)
        WidgetSnapshot.save(
            forecast: weatherService.forecast,
            observedTemperature: weatherService.currentObservation?.temperatureValue,
            observation: weatherService.currentObservation,
            hourly: weatherService.hourlyPeriods,
            alerts: weatherService.alerts,
            aqi: airQuality.snapshot?.aqi,
            uv: sun.snapshot?.uvIndex
        )
    }

    private func refreshIntelligence() async {
        intelligence.updateContext(
            forecast: weatherService.forecast,
            observation: weatherService.currentObservation,
            hourly: weatherService.hourlyPeriods,
            daily: weatherService.dailyForecasts,
            alerts: weatherService.alerts
        )
        await intelligence.generateSummaryIfNeeded()
    }
}

#Preview {
    ContentView()
}
