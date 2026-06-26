import SwiftUI
import CoreLocation
import MapKit

/// Material chrome for controls floating over the live map. Liquid Glass
/// composites on the Metal renderer, and glass-over-MKMapView is what kept
/// hitting the MTLStoreActionMultisampleResolve crash — material is Core
/// Animation-backed and immune, while looking nearly identical. Glass
/// remains on all non-map screens.
private extension View {
    func mapChrome<S: InsettableShape>(tint: Color? = nil, in shape: S) -> some View {
        self
            .background {
                if let tint { shape.fill(tint) }
            }
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.1)))
    }
}

struct RadarView: View {
    let forecast: ForecastSummary?
    let coordinate: CLLocationCoordinate2D?
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let locationStatus: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var radarSiteService = RadarSiteService()
    @StateObject private var stormTrackService = StormTrackService()
    @StateObject private var timeline = RadarTimelineController()
    @State private var selectedProduct: RadarProduct = .compositeReflectivity
    @State private var selectedScope: RadarScope = .national
    /// Until the user explicitly picks a scope, the camera opens on their
    /// area (~6.5°) rather than the scope's default framing.
    @State private var hasChosenScope = false
    @State private var selectedRadarSiteID: String?
    @AppStorage("radar_noise_filter") private var noiseFilter: RadarNoiseFilter = .light
    @AppStorage("radar_layer_lightning") private var showsLightning = false
    @AppStorage("radar_layer_alerts") private var showsAlertPolygons = true
    @AppStorage("radar_layer_tracks") private var showsStormTracks = true
    @State private var latestMapRect: MKMapRect = .world
    @State private var latestZoom: Int = 5
    @State private var tapDetail: RadarTapDetail?

    var body: some View {
        ZStack {
            RadarMapView(
                coordinate: coordinate,
                currentLocationCoordinate: currentLocationCoordinate,
                radarSites: radarSiteService.sites,
                selectedRadarSiteID: activeRadarSite?.radarID,
                showsRadarSites: selectedScope == .local,
                stormTracks: showsStormTracks ? stormTrackService.tracks : [],
                alertPolygons: showsAlertPolygons ? stormTrackService.alertPolygons : [],
                stormMarkers: showsStormTracks ? stormTrackService.stormMarkers : [],
                showsLightning: showsLightning,
                onSelectRadarSite: handleRadarSiteSelection,
                configuration: selectedConfiguration,
                spanDelta: selectedSpanDelta,
                timelineActive: !timeline.isLive,
                timelineFrameSource: timeline.currentSource,
                timelineAnimatesTransitions: timeline.isPlaying,
                onMapRegionChanged: { rect, zoom in
                    latestMapRect = rect
                    latestZoom = zoom
                    // Keep loop frames warmed for the visible area (deduped).
                    timeline.prepare(visibleMapRect: rect, zoom: zoom)
                },
                onMapTap: { coordinate in
                    inspectTap(at: coordinate)
                },
                onSelectStormMarker: { marker in
                    showStormMarkerDetail(marker)
                }
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if selectedProduct.supportsScopeSelection {
                            ForEach(RadarScope.allCases) { scope in
                                radarScopeButton(for: scope)
                            }
                        }

                        if selectedProduct.supportsNoiseFilter(scope: selectedScope) {
                            noiseFilterMenu
                        }

                        ForEach(RadarOverlayLayer.allCases) { layer in
                            layerToggleButton(for: layer)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if selectedScope == .local, let activeRadarSite {
                    siteBanner(for: activeRadarSite)
                        .padding(.horizontal, 16)
                }

                Spacer()

                if let tapDetail {
                    inspectorBubble(for: tapDetail)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                RadarLegend(product: selectedProduct, showsLightning: showsLightning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                timelineBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task(id: radarTaskID) {
            guard let coordinate else { return }
            async let radarSitesTask: Void = radarSiteService.loadNearestSite(for: coordinate)
            async let stormTracksTask: Void = stormTrackService.loadTracks(for: coordinate)
            _ = await (radarSitesTask, stormTracksTask)
            // Tell the timeline which scope/site to animate, then pre-warm
            // loop frames so the first play/scrub is instant.
            configureTimeline()
            timeline.prepare(visibleMapRect: latestMapRect, zoom: latestZoom)
        }
        .onChange(of: coordinate?.latitude) { _, _ in selectedRadarSiteID = nil }
        .onChange(of: coordinate?.longitude) { _, _ in selectedRadarSiteID = nil }
        .onChange(of: selectedScope) { _, _ in configureTimeline() }
        .onChange(of: activeRadarSite?.radarID) { _, _ in configureTimeline() }
    }

    /// Keeps the timeline controller in sync with the scope/site/product the
    /// user is viewing so the loop animates local single-site frames in local
    /// mode and the national mosaic otherwise.
    private func configureTimeline() {
        timeline.configure(
            scope: selectedScope,
            siteID: selectedScope == .local ? activeRadarSite?.radarID : nil,
            product: timelineProduct
        )
    }

    /// IEM RIDGE single-site product code for the active radar.
    private var timelineProduct: String {
        activeRadarSite?.kind == .tdwr ? "TZL" : "N0B"
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
            .mapChrome(in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer()

            ProductStatusBadge(
                title: timeline.isLive ? selectedProduct.shortTitle : "LOOP",
                subtitle: timeline.isLive ? productStatusLine : timeline.currentFrameLabel
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
            .mapChrome(in: Circle())
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
        .mapChrome(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Tap inspector

    /// Liquid-glass detail bubble for tapped storms, alerts, and echoes.
    private func inspectorBubble(for detail: RadarTapDetail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(severityColor(for: detail.severityKey))
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                ForEach(detail.lines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    tapDetail = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .mapChrome(
            tint: severityColor(for: detail.severityKey).opacity(0.14),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func severityColor(for key: String?) -> Color {
        switch key {
        case "extreme": return .purple
        case "severe": return .red
        case "moderate": return .orange
        case "minor": return .yellow
        default: return .cyan
        }
    }

    private func inspectTap(at coordinate: CLLocationCoordinate2D) {
        let minutes = timeline.minutesAgo
        let zoom = latestZoom
        let severityRank = ["extreme": 0, "severe": 1, "moderate": 2, "minor": 3]
        let hits = stormTrackService.alertPolygons
            .filter { $0.contains(coordinate) }
            .sorted { (severityRank[$0.severityKey] ?? 4) < (severityRank[$1.severityKey] ?? 4) }

        Task {
            let dbz = await RadarTapInspector.estimateDBZ(
                at: coordinate,
                minutesAgo: minutes,
                zoom: zoom
            )

            var lines: [String] = []
            if let dbz {
                lines.append("\(Int(dbz.rounded())) dBZ • \(ReflectivityScale.intensityWord(forDBZ: dbz))")
            } else {
                lines.append("No precipitation at this point")
            }

            let title: String
            let severityKey: String?
            if let top = hits.first {
                title = top.event
                severityKey = top.severityKey
                if let ends = top.endsText { lines.append(ends) }
                if hits.count > 1 {
                    lines.append("+\(hits.count - 1) more alert\(hits.count > 2 ? "s" : "") at this point")
                }
            } else {
                title = "Radar Inspector"
                severityKey = nil
            }

            lines.append(String(
                format: "%.2f°%@, %.2f°%@",
                abs(coordinate.latitude), coordinate.latitude >= 0 ? "N" : "S",
                abs(coordinate.longitude), coordinate.longitude >= 0 ? "E" : "W"
            ))

            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                tapDetail = RadarTapDetail(title: title, severityKey: severityKey, lines: lines)
            }
        }
    }

    private func showStormMarkerDetail(_ marker: StormMarker) {
        var lines: [String] = []
        if let motion = marker.motionText { lines.append(motion) }
        lines.append("Track shows projected 30-minute path")

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tapDetail = RadarTapDetail(
                title: marker.event,
                severityKey: marker.event.lowercased().contains("tornado") ? "extreme" : "severe",
                lines: lines
            )
        }
    }

    // MARK: - Timeline bar (always visible)

    private var timelineBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(timeline.isLive ? Color.green : Color.cyan)
                        .frame(width: 7, height: 7)
                    Text(timeline.currentFrameLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .animation(.none, value: timeline.currentFrameLabel)
                }

                // Always present — conditionally inserting children inside a
                // glass container crashes the renderer (see header comment).
                Button {
                    timeline.backToLive()
                } label: {
                    Text("Go Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.14), in: Capsule(style: .continuous))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(timeline.isLive ? 0 : 1)
                .allowsHitTesting(!timeline.isLive)

                Spacer()

                Menu {
                    Picker("Loop Length", selection: $timeline.loopDuration) {
                        ForEach(RadarLoopDuration.allCases) { duration in
                            Text(duration.title).tag(duration)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .bold))
                        Text(timeline.loopDuration.title)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                    .contentShape(Capsule())
                }

                Button {
                    timeline.playbackSpeed = timeline.playbackSpeed == 1.0 ? 2.0 : 1.0
                } label: {
                    Text(timeline.playbackSpeed == 1.0 ? "1×" : "2×")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button {
                    if timeline.isPlaying {
                        timeline.pause()
                    } else {
                        timeline.play(visibleMapRect: latestMapRect, zoom: latestZoom)
                    }
                } label: {
                    Image(systemName: timeline.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                timelineScrubber
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        // ultraThinMaterial, NOT glassEffect: this bar repaints on every
        // playback tick, and the glass Metal renderer crashes under
        // continuous updates (MTLStoreActionMultisampleResolve assertion).
        // Material is Core Animation-backed and immune.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        }
    }

    private var timelineScrubber: some View {
        GeometryReader { geo in
            let frameCount = max(1, timeline.frames.count)
            let frameIndex = timeline.position
            let ratio = frameCount > 1 ? CGFloat(frameIndex) / CGFloat(frameCount - 1) : 0
            let trackWidth = geo.size.width
            let thumbX = trackWidth * ratio

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: 4)

                // Never zero-width: zero-size fills emit "clip: empty path"
                // and feed the zero-drawable Metal crash.
                Capsule()
                    .fill(.cyan.opacity(0.9))
                    .frame(width: max(5, thumbX), height: 4)

                HStack(spacing: 0) {
                    ForEach(0..<frameCount, id: \.self) { i in
                        Circle()
                            .fill(i <= frameIndex ? Color.cyan : Color.white.opacity(0.35))
                            .frame(width: 5, height: 5)
                        if i < frameCount - 1 { Spacer(minLength: 0) }
                    }
                }

                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, thumbX - 9))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        timeline.pause()
                        // Warm frames so scrubbing shows changing imagery
                        // immediately, not after each network round-trip.
                        timeline.prepare(visibleMapRect: latestMapRect, zoom: latestZoom)
                        let clamped = max(0, min(trackWidth, value.location.x))
                        let index = frameCount > 1
                            ? Int((clamped / trackWidth) * CGFloat(frameCount - 1) + 0.5)
                            : 0
                        timeline.seek(to: index)
                    }
            )
        }
        .frame(height: 18)
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
        .mapChrome(
            tint: noiseFilter == .off ? nil : Color.cyan.opacity(0.18),
            in: Capsule(style: .continuous)
        )
    }

    private var selectedSpanDelta: Double {
        hasChosenScope ? selectedScope.spanDelta : 6.5
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
                timeline.backToLive()
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
        .mapChrome(
            tint: isSelected ? Color.white.opacity(0.28) : nil,
            in: Capsule(style: .continuous)
        )
    }

    @ViewBuilder
    private func layerToggleButton(for layer: RadarOverlayLayer) -> some View {
        let isOn = layerBinding(for: layer).wrappedValue
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                layerBinding(for: layer).wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: layer.symbolName)
                    .font(.system(size: 10, weight: .bold))
                Text(layer.title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? layerTint(for: layer) : .white.opacity(0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .mapChrome(
            tint: isOn ? layerTint(for: layer).opacity(0.2) : nil,
            in: Capsule(style: .continuous)
        )
    }

    private func layerBinding(for layer: RadarOverlayLayer) -> Binding<Bool> {
        switch layer {
        case .lightning: return $showsLightning
        case .alerts: return $showsAlertPolygons
        case .stormTracks: return $showsStormTracks
        }
    }

    private func layerTint(for layer: RadarOverlayLayer) -> Color {
        switch layer {
        case .lightning: return .yellow
        case .alerts: return .orange
        case .stormTracks: return .pink
        }
    }

    @ViewBuilder
    private func radarScopeButton(for scope: RadarScope) -> some View {
        let isSelected = selectedScope == scope
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedScope = scope
                hasChosenScope = true
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
        .mapChrome(
            tint: isSelected ? Color.cyan.opacity(0.32) : nil,
            in: Capsule(style: .continuous)
        )
    }

    private func handleRadarSiteSelection(_ site: RadarSite) {
        guard site.isOnline else { return }
        // Idempotency guard: re-selecting the active site must not retrigger
        // state changes (and the resulting overlay/glass rebuild).
        guard selectedScope != .local || selectedRadarSiteID != site.radarID else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selectedScope = .local
            hasChosenScope = true
            selectedRadarSiteID = site.radarID
        }
    }
}
