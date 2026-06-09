import SwiftUI
import CoreLocation

struct RadarView: View {
    let forecast: ForecastSummary?
    let coordinate: CLLocationCoordinate2D?
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let locationStatus: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var radarSiteService = RadarSiteService()
    @StateObject private var stormTrackService = StormTrackService()
    @State private var selectedProduct: RadarProduct = .compositeReflectivity
    @State private var selectedScope: RadarScope = .national
    @State private var selectedRadarSiteID: String?
    @AppStorage("radar_noise_filter") private var noiseFilter: RadarNoiseFilter = .light

    var body: some View {
        ZStack {
            RadarMapView(
                coordinate: coordinate,
                currentLocationCoordinate: currentLocationCoordinate,
                radarSites: radarSiteService.sites,
                selectedRadarSiteID: activeRadarSite?.radarID,
                showsRadarSites: true,
                stormTracks: stormTrackService.tracks,
                onSelectRadarSite: handleRadarSiteSelection,
                configuration: selectedConfiguration,
                spanDelta: selectedSpanDelta
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                header

                // Plain HStacks (no GlassEffectContainer): containers with
                // conditionally inserted children trip "glassEffect() tried to
                // update multiple times per frame" and can crash the renderer.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RadarProduct.allCases) { product in
                            radarProductButton(for: product)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if selectedProduct.supportsScopeSelection || selectedProduct.supportsNoiseFilter(scope: selectedScope) {
                    HStack(spacing: 8) {
                        if selectedProduct.supportsScopeSelection {
                            ForEach(RadarScope.allCases) { scope in
                                radarScopeButton(for: scope)
                            }
                        }

                        if selectedProduct.supportsNoiseFilter(scope: selectedScope) {
                            noiseFilterMenu
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }

                if selectedScope == .local, let activeRadarSite {
                    siteBanner(for: activeRadarSite)
                        .padding(.horizontal, 16)
                }

                Spacer()
            }
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task(id: radarTaskID) {
            guard let coordinate else { return }
            async let radarSitesTask: Void = radarSiteService.loadNearestSite(for: coordinate)
            async let stormTracksTask: Void = stormTrackService.loadTracks(for: coordinate)
            _ = await (radarSitesTask, stormTracksTask)
        }
        .onChange(of: coordinate?.latitude) { _, _ in selectedRadarSiteID = nil }
        .onChange(of: coordinate?.longitude) { _, _ in selectedRadarSiteID = nil }
    }

    // MARK: - Overlay chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Radar")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(activeTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Spacer()

            ProductStatusBadge(
                title: selectedProduct.shortTitle,
                subtitle: productStatusLine
            )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 16)
    }

    private func siteBanner(for site: RadarSite) -> some View {
        Button {
            selectedRadarSiteID = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(site.radarID) • \(site.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)

                    Text("Tap another site beacon on the map to switch local radar.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if selectedRadarSiteID != nil {
                    Text("Nearest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // MARK: - Computed state

    private var selectedConfiguration: RadarLayerConfiguration? {
        selectedProduct.configuration(
            for: coordinate,
            scope: selectedScope,
            nearestSite: activeRadarSite,
            noiseFilter: noiseFilter
        )
    }

    private var noiseFilterMenu: some View {
        Menu {
            Picker("Noise Filter", selection: $noiseFilter) {
                ForEach(RadarNoiseFilter.allCases) { level in
                    Label(level.title, systemImage: level == .off ? "circle.slash" : "line.3.horizontal.decrease")
                        .tag(level)
                }
            }

            Divider()

            Text(noiseFilter.detail)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle\(noiseFilter == .off ? "" : ".fill")")
                    .font(.caption.weight(.bold))
                Text(noiseFilter == .off ? "Filter" : "Filter: \(noiseFilter.title)")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(noiseFilter == .off ? .white.opacity(0.72) : .cyan)
            .contentShape(Capsule())
        }
        .glassEffect(
            noiseFilter == .off ? .regular.interactive() : .regular.tint(.cyan.opacity(0.18)).interactive(),
            in: .capsule
        )
    }

    private var selectedSpanDelta: Double {
        selectedScope == .local ? 1.8 : 38.0
    }

    private var activeTitle: String {
        forecast.map { "\($0.locationName), \($0.state)" } ?? "National Weather Service"
    }

    private var productStatusLine: String {
        selectedScope == .local
            ? (activeRadarSite?.radarID ?? "Site search")
            : RadarDomain.domain(for: coordinate).title
    }

    private var activeRadarSite: RadarSite? {
        if let selectedRadarSiteID,
           let selected = radarSiteService.sites.first(where: { $0.radarID == selectedRadarSiteID }),
           selected.isOnline {
            return selected
        }
        return radarSiteService.nearestSite
    }

    private var radarTaskID: String {
        guard let coordinate else { return "no-radar-coordinate" }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }

    // MARK: - Controls

    @ViewBuilder
    private func radarProductButton(for product: RadarProduct) -> some View {
        let isSelected = selectedProduct == product
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedProduct = product
            }
        } label: {
            Text(product.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.74))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.white.opacity(0.28)).interactive() : .regular.interactive(),
            in: .capsule
        )
    }

    @ViewBuilder
    private func radarScopeButton(for scope: RadarScope) -> some View {
        let isSelected = selectedScope == scope
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedScope = scope
            }
        } label: {
            Text(scope.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.cyan.opacity(0.32)).interactive() : .regular.interactive(),
            in: .capsule
        )
    }

    private func handleRadarSiteSelection(_ site: RadarSite) {
        guard site.isOnline else { return }
        // Idempotency guard: re-selecting the active site must not retrigger
        // state changes (and the resulting overlay/glass rebuild).
        guard selectedScope != .local || selectedRadarSiteID != site.radarID else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selectedScope = .local
            selectedRadarSiteID = site.radarID
        }
    }
}
