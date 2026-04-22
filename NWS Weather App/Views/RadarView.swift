import SwiftUI
import CoreLocation

struct RadarView: View {
    let forecast: ForecastSummary?
    let coordinate: CLLocationCoordinate2D?
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let isLoading: Bool
    let locationStatus: String

    @StateObject private var radarSiteService = RadarSiteService()
    @StateObject private var stormTrackService = StormTrackService()
    @State private var selectedProduct: RadarProduct = .compositeReflectivity
    @State private var selectedScope: RadarScope = .national
    @State private var selectedRadarSiteID: String?

    var body: some View {
        ZStack {
            RadarMapView(
                coordinate: coordinate,
                currentLocationCoordinate: currentLocationCoordinate,
                radarSites: displayedRadarSites,
                selectedRadarSiteID: activeRadarSite?.radarID,
                showsRadarSites: selectedScope == .local,
                stormTracks: stormTrackService.tracks,
                onSelectRadarSite: handleRadarSiteSelection,
                configuration: selectedConfiguration,
                spanDelta: selectedSpanDelta
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Radar")
                                .font(.system(size: 24, weight: .bold, design: .rounded))

                            Text(activeTitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }

                        Spacer()

                        ProductStatusBadge(
                            title: selectedProduct.shortTitle,
                            subtitle: productStatusLine
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RadarProduct.allCases) { product in
                                radarProductButton(for: product)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.12), in: Capsule(style: .continuous))
                    }

                    if selectedProduct.supportsScopeSelection {
                        HStack(spacing: 8) {
                            ForEach(RadarScope.allCases) { scope in
                                radarScopeButton(for: scope)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.12), in: Capsule(style: .continuous))
                    }

                    if selectedScope == .local, let activeRadarSite {
                        Button {
                            selectedRadarSiteID = nil
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(activeRadarSite.radarID) • \(activeRadarSite.name)")
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
                            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: radarTaskID) {
            guard let coordinate else { return }
            async let radarSitesTask: Void = radarSiteService.loadNearestSite(for: coordinate)
            async let stormTracksTask: Void = stormTrackService.loadTracks(for: coordinate)
            _ = await (radarSitesTask, stormTracksTask)
        }
        .onChange(of: coordinate?.latitude) { _, _ in selectedRadarSiteID = nil }
        .onChange(of: coordinate?.longitude) { _, _ in selectedRadarSiteID = nil }
    }

    private var selectedConfiguration: RadarLayerConfiguration? {
        selectedProduct.configuration(for: coordinate, scope: selectedScope, nearestSite: activeRadarSite)
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
           let selected = radarSiteService.sites.first(where: { $0.radarID == selectedRadarSiteID }) {
            return selected
        }
        return radarSiteService.nearestSite
    }

    private var displayedRadarSites: [RadarSite] {
        guard let center = coordinate else { return [] }
        return radarSiteService.nearbySites(for: center, limit: 12)
    }

    private var radarTaskID: String {
        guard let coordinate else { return "no-radar-coordinate" }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }

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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.74))
                .background(Capsule(style: .continuous).fill(isSelected ? .white.opacity(0.18) : .white.opacity(0.06)))
                .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(isSelected ? 0.22 : 0.08)) }
        }
        .buttonStyle(.plain)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                .background(Capsule(style: .continuous).fill(isSelected ? .cyan.opacity(0.22) : .white.opacity(0.05)))
                .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(isSelected ? 0.22 : 0.08)) }
        }
        .buttonStyle(.plain)
    }

    private func handleRadarSiteSelection(_ site: RadarSite) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selectedScope = .local
            selectedRadarSiteID = site.radarID
        }
    }
}
