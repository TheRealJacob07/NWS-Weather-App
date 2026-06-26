import MapKit
import SwiftUI

struct RadarMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D?
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let radarSites: [RadarSite]
    let selectedRadarSiteID: String?
    let showsRadarSites: Bool
    let stormTracks: [StormTrack]
    let alertPolygons: [AlertPolygon]
    let stormMarkers: [StormMarker]
    let showsLightning: Bool
    let onSelectRadarSite: (RadarSite) -> Void
    let configuration: RadarLayerConfiguration?
    let spanDelta: Double
    /// When true, the historical loop frame replaces the live WMS product.
    let timelineActive: Bool
    let timelineFrameSource: RadarFrameSource
    /// Crossfade between loop frames (used during playback).
    let timelineAnimatesTransitions: Bool
    let onMapRegionChanged: ((MKMapRect, Int) -> Void)?
    let onMapTap: ((CLLocationCoordinate2D) -> Void)?
    let onSelectStormMarker: ((StormMarker) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectRadarSite: onSelectRadarSite)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.showsCompass = false
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false

        // Radar data is useless past ~city scale, and street-level zoom
        // multiplies tile requests for nothing. Capping the camera keeps
        // pans/zooms inside the range where tiles exist and load fast.
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 25_000,
            maxCenterCoordinateDistance: 14_000_000
        )

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        context.coordinator.onMapRegionChanged = onMapRegionChanged
        context.coordinator.onMapTap = onMapTap
        context.coordinator.onSelectStormMarker = onSelectStormMarker
        updateOverlay(on: mapView, coordinator: context.coordinator)
        updateLightningOverlay(on: mapView, coordinator: context.coordinator)
        updateTimelineOverlay(on: mapView, coordinator: context.coordinator)
        updateAlertPolygonOverlays(on: mapView, coordinator: context.coordinator)
        updateStormTrackOverlays(on: mapView, coordinator: context.coordinator)
        updateStormMarkerAnnotations(on: mapView, coordinator: context.coordinator)
        updateRadarSiteAnnotations(on: mapView, coordinator: context.coordinator)
        setVisibleRegion(on: mapView, coordinator: context.coordinator, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onMapRegionChanged = onMapRegionChanged
        context.coordinator.onMapTap = onMapTap
        context.coordinator.onSelectStormMarker = onSelectStormMarker
        updateOverlay(on: mapView, coordinator: context.coordinator)
        updateLightningOverlay(on: mapView, coordinator: context.coordinator)
        updateTimelineOverlay(on: mapView, coordinator: context.coordinator)
        updateAlertPolygonOverlays(on: mapView, coordinator: context.coordinator)
        updateStormTrackOverlays(on: mapView, coordinator: context.coordinator)
        updateStormMarkerAnnotations(on: mapView, coordinator: context.coordinator)
        updateRadarSiteAnnotations(on: mapView, coordinator: context.coordinator)
        setVisibleRegion(on: mapView, coordinator: context.coordinator, animated: true)
    }

    // MARK: - Static radar overlay

    private func updateOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        if timelineActive {
            if let radarOverlay = coordinator.radarOverlay {
                mapView.removeOverlay(radarOverlay)
                coordinator.radarOverlay = nil
                coordinator.currentConfiguration = nil
            }
            return
        }

        guard coordinator.currentConfiguration != configuration else { return }

        if let radarOverlay = coordinator.radarOverlay {
            mapView.removeOverlay(radarOverlay)
            coordinator.radarOverlay = nil
        }

        if let configuration {
            let overlay = NWSRadarTileOverlay(configuration: configuration)
            overlay.canReplaceMapContent = false
            mapView.addOverlay(overlay, level: .aboveLabels)
            coordinator.radarOverlay = overlay
        }

        coordinator.currentConfiguration = configuration
    }

    // MARK: - Lightning overlay

    private func updateLightningOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        if showsLightning {
            guard coordinator.lightningOverlay == nil else { return }
            let overlay = NWSRadarTileOverlay(configuration: RadarOverlayLayer.lightningConfiguration)
            overlay.canReplaceMapContent = false
            mapView.addOverlay(overlay, level: .aboveLabels)
            coordinator.lightningOverlay = overlay
        } else if let overlay = coordinator.lightningOverlay {
            mapView.removeOverlay(overlay)
            coordinator.lightningOverlay = nil
        }
    }

    // MARK: - Alert polygon overlays

    /// One MKMultiPolygon per severity (≤5 renderers total, instead of one
    /// renderer per alert), restricted to geometry near the visible map —
    /// off-screen alerts cost nothing.
    private func updateAlertPolygonOverlays(on mapView: MKMapView, coordinator: Coordinator) {
        let visible = Self.paddedVisibleRect(of: mapView)
        let onScreen = alertPolygons.filter { Self.boundingRect(of: $0.coordinates).intersects(visible) }

        let key = onScreen.map(\.id).joined(separator: "|")
        guard coordinator.alertPolygonKey != key else { return }
        coordinator.alertPolygonKey = key

        if !coordinator.alertPolygonOverlays.isEmpty {
            mapView.removeOverlays(coordinator.alertPolygonOverlays)
            coordinator.alertPolygonOverlays.removeAll()
        }

        let grouped = Dictionary(grouping: onScreen, by: \.severityKey)
        let overlays = grouped.map { severityKey, alerts in
            let polygons = alerts.map { MKPolygon(coordinates: $0.coordinates, count: $0.coordinates.count) }
            let multi = MKMultiPolygon(polygons)
            multi.title = severityKey
            return multi
        }
        mapView.addOverlays(overlays, level: .aboveLabels)
        coordinator.alertPolygonOverlays = overlays
    }

    /// Visible map rect padded 50% so slight pans don't trigger rebuilds.
    nonisolated static func paddedVisibleRect(of mapView: MKMapView) -> MKMapRect {
        mapView.visibleMapRect.insetBy(
            dx: -mapView.visibleMapRect.width * 0.5,
            dy: -mapView.visibleMapRect.height * 0.5
        )
    }

    nonisolated static func boundingRect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return rect
    }

    // MARK: - Storm markers

    private func updateStormMarkerAnnotations(on mapView: MKMapView, coordinator: Coordinator) {
        let ids = stormMarkers.map(\.id)
        guard coordinator.stormMarkerIDs != ids else { return }

        if !coordinator.stormMarkerAnnotations.isEmpty {
            mapView.removeAnnotations(coordinator.stormMarkerAnnotations)
            coordinator.stormMarkerAnnotations.removeAll()
        }

        let annotations = stormMarkers.map { StormMarkerAnnotation(marker: $0) }
        mapView.addAnnotations(annotations)
        coordinator.stormMarkerAnnotations = annotations
        coordinator.stormMarkerIDs = ids
    }

    // MARK: - Timeline (historical loop) overlay

    /// Double-buffered loop frames: the next frame loads into the hidden
    /// back overlay, then the two renderers crossfade — no flicker between
    /// frames, RadarScope-style. Falls back to an instant swap while
    /// scrubbing (crossfades would lag behind the finger).
    private func updateTimelineOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        guard timelineActive else {
            coordinator.fadeTask?.cancel()
            coordinator.fadeTask = nil
            for overlay in coordinator.timelineOverlays {
                mapView.removeOverlay(overlay)
            }
            coordinator.timelineOverlays.removeAll()
            coordinator.timelineRenderers.removeAll()
            coordinator.timelineFrontIndex = 0
            coordinator.timelineFrameSource = nil
            return
        }

        if coordinator.timelineOverlays.isEmpty {
            let front = RidgeTimelineTileOverlay()
            front.source = timelineFrameSource
            let back = RidgeTimelineTileOverlay()
            back.source = timelineFrameSource
            mapView.addOverlay(front, level: .aboveLabels)
            mapView.addOverlay(back, level: .aboveLabels)
            coordinator.timelineOverlays = [front, back]
            coordinator.timelineFrontIndex = 0
            coordinator.timelineFrameSource = timelineFrameSource
            return
        }

        guard timelineFrameSource != coordinator.timelineFrameSource else { return }
        coordinator.timelineFrameSource = timelineFrameSource

        let backIndex = 1 - coordinator.timelineFrontIndex
        let front = coordinator.timelineOverlays[coordinator.timelineFrontIndex]
        let back = coordinator.timelineOverlays[backIndex]

        guard let frontRenderer = coordinator.timelineRenderers[ObjectIdentifier(front)],
              let backRenderer = coordinator.timelineRenderers[ObjectIdentifier(back)] else {
            // Renderers not realized yet (first frames) — update in place.
            front.source = timelineFrameSource
            coordinator.timelineRenderers[ObjectIdentifier(front)]?.reloadData()
            return
        }

        back.source = timelineFrameSource
        backRenderer.reloadData()
        coordinator.timelineFrontIndex = backIndex

        coordinator.fadeTask?.cancel()
        if timelineAnimatesTransitions {
            coordinator.fadeTask = Task { @MainActor in
                // Give cached tiles one beat to draw, then crossfade.
                try? await Task.sleep(nanoseconds: 60_000_000)
                for step in 1...4 {
                    guard !Task.isCancelled else { break }
                    let alpha = CGFloat(step) / 4.0
                    backRenderer.alpha = alpha
                    frontRenderer.alpha = 1.0 - alpha
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }
                backRenderer.alpha = 1.0
                frontRenderer.alpha = 0.0
            }
        } else {
            backRenderer.alpha = 1.0
            frontRenderer.alpha = 0.0
        }
    }

    // MARK: - Storm track overlays

    /// One MKMultiPolyline per track style (2 renderers max), viewport
    /// filtered like the alert polygons.
    private func updateStormTrackOverlays(on mapView: MKMapView, coordinator: Coordinator) {
        let visible = Self.paddedVisibleRect(of: mapView)
        let onScreen = stormTracks.filter { Self.boundingRect(of: $0.coordinates).intersects(visible) }

        let key = onScreen.map { $0.id.uuidString }.joined(separator: "|")
        guard coordinator.stormTrackKey != key else { return }
        coordinator.stormTrackKey = key

        if !coordinator.stormTrackOverlays.isEmpty {
            mapView.removeOverlays(coordinator.stormTrackOverlays)
            coordinator.stormTrackOverlays.removeAll()
        }

        let grouped = Dictionary(grouping: onScreen, by: \.style)
        let overlays = grouped.map { style, tracks in
            let polylines = tracks.map { MKPolyline(coordinates: $0.coordinates, count: $0.coordinates.count) }
            let multi = MKMultiPolyline(polylines)
            multi.title = style.rawValue
            return multi
        }
        mapView.addOverlays(overlays, level: .aboveLabels)
        coordinator.stormTrackOverlays = overlays
    }

    private func updateRadarSiteAnnotations(on mapView: MKMapView, coordinator: Coordinator) {
        let siteIDs = showsRadarSites ? radarSites.map(\.radarID) : []
        let selectionChanged = coordinator.selectedRadarSiteID != selectedRadarSiteID
        let sitesChanged = coordinator.radarSiteIDs != siteIDs
        guard selectionChanged || sitesChanged else { return }

        if !coordinator.radarSiteAnnotations.isEmpty {
            mapView.removeAnnotations(coordinator.radarSiteAnnotations)
            coordinator.radarSiteAnnotations.removeAll()
        }

        guard showsRadarSites else {
            coordinator.radarSiteIDs = []
            coordinator.selectedRadarSiteID = selectedRadarSiteID
            return
        }

        let annotations = radarSites.map { RadarSiteAnnotation(site: $0) }
        mapView.addAnnotations(annotations)
        coordinator.radarSiteAnnotations = annotations
        coordinator.radarSiteIDs = siteIDs
        coordinator.selectedRadarSiteID = selectedRadarSiteID
        // Note: never call mapView.selectAnnotation(_:animated:) here — this
        // method runs inside updateUIView, and a programmatic selection fires
        // the didSelect delegate, which mutates SwiftUI state mid-update
        // ("Modifying state during view update" → corrupted glass rendering).
        // The active site is highlighted via marker tint instead.
    }

    private func setVisibleRegion(on mapView: MKMapView, coordinator: Coordinator, animated: Bool) {
        let coordinateChanged = !coordinatesEqual(coordinator.lastCoordinate, coordinate)
        let spanChanged = coordinator.lastSpanDelta != spanDelta
        guard coordinateChanged || spanChanged else { return }

        let region: MKCoordinateRegion
        if let coordinate {
            region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
            )
        } else {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 28.0, longitudeDelta: 36.0)
            )
        }

        mapView.setRegion(region, animated: animated)
        coordinator.lastCoordinate = coordinate
        coordinator.lastSpanDelta = spanDelta
    }

    private func coordinatesEqual(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(l), .some(r)):
            return abs(l.latitude - r.latitude) < 0.0001 && abs(l.longitude - r.longitude) < 0.0001
        default: return false
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let onSelectRadarSite: (RadarSite) -> Void
        var onMapRegionChanged: ((MKMapRect, Int) -> Void)?
        var currentConfiguration: RadarLayerConfiguration?
        fileprivate var radarOverlay: NWSRadarTileOverlay?
        var lastCoordinate: CLLocationCoordinate2D?
        var lastSpanDelta: Double?
        fileprivate var radarSiteAnnotations: [RadarSiteAnnotation] = []
        var radarSiteIDs: [String] = []
        var selectedRadarSiteID: String?
        var stormTrackOverlays: [MKMultiPolyline] = []
        var stormTrackKey = ""
        fileprivate var lightningOverlay: NWSRadarTileOverlay?
        var alertPolygonOverlays: [MKMultiPolygon] = []
        var alertPolygonKey = ""
        fileprivate var stormMarkerAnnotations: [StormMarkerAnnotation] = []
        var stormMarkerIDs: [String] = []
        fileprivate var timelineOverlays: [RidgeTimelineTileOverlay] = []
        var timelineRenderers: [ObjectIdentifier: MKTileOverlayRenderer] = [:]
        var timelineFrontIndex = 0
        var timelineFrameSource: RadarFrameSource?
        var fadeTask: Task<Void, Never>?
        var onMapTap: ((CLLocationCoordinate2D) -> Void)?
        var onSelectStormMarker: ((StormMarker) -> Void)?

        init(onSelectRadarSite: @escaping (RadarSite) -> Void) {
            self.onSelectRadarSite = onSelectRadarSite
        }

        // Run alongside MapKit's own gestures so pan/zoom keep working.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)

            // Taps on annotation views are handled by didSelect.
            if let hit = mapView.hitTest(point, with: nil),
               sequence(first: hit, next: { $0.superview }).contains(where: { $0 is MKAnnotationView }) {
                return
            }

            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            // Defer so the callback never mutates SwiftUI state mid-gesture/
            // view-update pass.
            DispatchQueue.main.async { [onMapTap] in
                onMapTap?(coordinate)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let callback = onMapRegionChanged else { return }
            let zoom = Self.zoomLevel(for: mapView)
            callback(mapView.visibleMapRect, zoom)
        }

        private static func zoomLevel(for mapView: MKMapView) -> Int {
            guard mapView.bounds.width > 0 else { return 5 }
            let scale = Double(mapView.bounds.width) / mapView.visibleMapRect.size.width
            let zoom = log2(scale * MKMapSize.world.width / 256.0)
            return max(2, min(Int(zoom), 14))
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? RidgeTimelineTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                // Front overlay starts visible, back starts hidden.
                let isFront = timelineOverlays.indices.contains(timelineFrontIndex)
                    && timelineOverlays[timelineFrontIndex] === tileOverlay
                renderer.alpha = isFront ? 1.0 : 0.0
                timelineRenderers[ObjectIdentifier(tileOverlay)] = renderer
                return renderer
            }

            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }

            if let multiPolygon = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                let color = Self.severityColor(for: multiPolygon.title)
                renderer.fillColor = color.withAlphaComponent(0.12)
                renderer.strokeColor = color.withAlphaComponent(0.85)
                renderer.lineWidth = 1.5
                return renderer
            }

            if let multiPolyline = overlay as? MKMultiPolyline {
                let renderer = MKMultiPolylineRenderer(multiPolyline: multiPolyline)
                let isWarning = multiPolyline.title == StormTrackStyle.warningArea.rawValue
                renderer.lineWidth = isWarning ? 3 : 4
                renderer.strokeColor = isWarning
                    ? UIColor.systemOrange.withAlphaComponent(0.85)
                    : UIColor.systemPink.withAlphaComponent(0.92)
                if isWarning { renderer.lineDashPattern = [8, 6] }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        static func severityColor(for severityKey: String?) -> UIColor {
            switch severityKey {
            case "extreme": return UIColor.systemPurple
            case "severe": return UIColor.systemRed
            case "moderate": return UIColor.systemOrange
            case "minor": return UIColor.systemYellow
            default: return UIColor.systemGray
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let marker = annotation as? StormMarkerAnnotation {
                let identifier = "StormMarker"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: marker, reuseIdentifier: identifier)
                view.annotation = marker
                view.canShowCallout = false // selection opens the glass inspector instead
                view.markerTintColor = marker.isTornado ? .systemRed : .systemOrange
                view.glyphImage = UIImage(systemName: marker.isTornado ? "tornado" : "cloud.bolt.fill")
                view.glyphTintColor = .white
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                view.displayPriority = .required
                view.clusteringIdentifier = nil
                return view
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let identifier = "RadarSiteCluster"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                view.annotation = cluster
                view.markerTintColor = UIColor(red: 0.13, green: 0.45, blue: 0.85, alpha: 1.0)
                view.glyphTintColor = .white
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                return view
            }

            guard let annotation = annotation as? RadarSiteAnnotation else { return nil }

            let identifier = "RadarSiteBeacon"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.clusteringIdentifier = "radar-sites"
            if annotation.site.isOnline {
                view.markerTintColor = annotation.site.radarID == selectedRadarSiteID
                    ? .systemTeal
                    : UIColor(red: 0.15, green: 0.58, blue: 1.0, alpha: 1.0)
                view.glyphImage = nil
                view.glyphText = annotation.site.radarID
            } else {
                view.markerTintColor = .systemRed
                view.glyphText = nil
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
            }
            view.glyphTintColor = .white
            view.titleVisibility = .visible
            view.subtitleVisibility = .visible
            view.displayPriority = annotation.site.isOnline ? .defaultHigh : .defaultLow
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let stormMarker = annotation as? StormMarkerAnnotation {
                mapView.deselectAnnotation(stormMarker, animated: false)
                let marker = stormMarker.marker
                DispatchQueue.main.async { [onSelectStormMarker] in
                    onSelectStormMarker?(marker)
                }
                return
            }

            if let cluster = annotation as? MKClusterAnnotation {
                // Tapping a cluster zooms in to reveal its member sites.
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }

            guard let annotation = annotation as? RadarSiteAnnotation else { return }
            guard annotation.site.isOnline else {
                // Offline radars are informational only — show the callout
                // briefly but never switch the feed to a dead site.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    mapView.deselectAnnotation(annotation, animated: true)
                }
                return
            }
            selectedRadarSiteID = annotation.site.radarID
            let site = annotation.site
            // Defer to the next runloop turn so the state change never lands
            // inside a SwiftUI/MapKit view update pass.
            DispatchQueue.main.async { [onSelectRadarSite] in
                onSelectRadarSite(site)
            }
        }
    }
}

fileprivate final class StormMarkerAnnotation: NSObject, MKAnnotation {
    let marker: StormMarker
    var coordinate: CLLocationCoordinate2D { marker.coordinate }
    var title: String? { marker.event }
    var subtitle: String? { marker.motionText }
    var isTornado: Bool { marker.event.lowercased().contains("tornado") }

    init(marker: StormMarker) {
        self.marker = marker
    }
}

fileprivate final class RadarSiteAnnotation: NSObject, MKAnnotation {
    let site: RadarSite
    var coordinate: CLLocationCoordinate2D { site.coordinate }
    var title: String? { site.name }
    var subtitle: String? { site.isOnline ? site.radarID : "\(site.radarID) — Offline" }

    init(site: RadarSite) {
        self.site = site
    }
}

/// `nonisolated` is required: the project uses default MainActor isolation,
/// but MapKit calls `loadTile`/`url(forTilePath:)` on background queues and
/// the URLSession completion runs off-main. Without this, the runtime's
/// isolation assertion aborts the app the moment a filtered tile loads.
fileprivate nonisolated final class NWSRadarTileOverlay: MKTileOverlay {
    let configuration: RadarLayerConfiguration
    private let tileDimension = 256.0
    private let worldWidth = MKMapSize.world.width

    private let minimumDBZ: Double?

    init(configuration: RadarLayerConfiguration) {
        self.configuration = configuration
        self.minimumDBZ = configuration.minimumDBZ
        super.init(urlTemplate: nil)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping @Sendable (Data?, Error?) -> Void) {
        guard let minimumDBZ else {
            // Unfiltered tiles still go through the shared cached session
            // (instead of MKTileOverlay's default loader) so panning back
            // over an area redraws from cache instead of re-fetching WMS.
            let request = URLRequest(url: url(forTilePath: path))
            NetworkSessions.tiles.dataTask(with: request) { data, response, error in
                if let data,
                   let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                    result(data, nil)
                } else {
                    result(nil, error)
                }
            }.resume()
            return
        }

        let request = URLRequest(url: url(forTilePath: path))
        NetworkSessions.tiles.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                result(nil, error)
                return
            }
            // Runs on URLSession's background queue — the LUT build and
            // per-pixel work never touch the main thread.
            let lut = Self.keepLUT(forMinimumDBZ: minimumDBZ)
            result(Self.filteredTileData(from: data, keepLUT: lut), nil)
        }.resume()
    }

    // MARK: - Noise filtering

    /// 5-bit-per-channel RGB lookup (32768 entries): true = keep the pixel.
    /// Expensive to build, so it is computed once per threshold on a
    /// background queue and cached for the life of the app.
    nonisolated(unsafe) private static var lutCache: [Int: [Bool]] = [:]
    private static let lutLock = NSLock()

    private static func keepLUT(forMinimumDBZ minimumDBZ: Double) -> [Bool] {
        let key = Int((minimumDBZ * 100).rounded())
        lutLock.lock()
        defer { lutLock.unlock() }

        if let cached = lutCache[key] { return cached }
        let lut = makeKeepLUT(minimumDBZ: minimumDBZ)
        lutCache[key] = lut
        return lut
    }

    private static func makeKeepLUT(minimumDBZ: Double) -> [Bool] {
        var lut = [Bool](repeating: true, count: 32768)
        for r5 in 0..<32 {
            let r = r5 << 3 | r5 >> 2
            for g5 in 0..<32 {
                let g = g5 << 3 | g5 >> 2
                for b5 in 0..<32 {
                    let b = b5 << 3 | b5 >> 2
                    let dbz = ReflectivityScale.dbz(red: r, green: g, blue: b)
                    lut[r5 << 10 | g5 << 5 | b5] = dbz >= minimumDBZ
                }
            }
        }
        return lut
    }

    private static func filteredTileData(from data: Data, keepLUT: [Bool]) -> Data {
        guard let cgImage = UIImage(data: data)?.cgImage else { return data }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return data }

        // Let CoreGraphics own the pixel buffer (bytesPerRow: 0 = auto).
        // Drawing into our own Swift-managed memory is unsafe here because
        // makeImage() may reference the buffer beyond this scope.
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return data }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let baseAddress = context.data else { return data }

        let bytesPerRow = context.bytesPerRow
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                let alpha = Int(pixels[offset + 3])
                if alpha < 32 { continue }

                var red = Int(pixels[offset])
                var green = Int(pixels[offset + 1])
                var blue = Int(pixels[offset + 2])
                if alpha < 255 {
                    // Un-premultiply so edge pixels match the palette.
                    red = min(255, red * 255 / alpha)
                    green = min(255, green * 255 / alpha)
                    blue = min(255, blue * 255 / alpha)
                }

                let index = (red >> 3) << 10 | (green >> 3) << 5 | (blue >> 3)
                if !keepLUT[index] {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                }
            }
        }

        guard let filtered = context.makeImage() else { return data }
        return UIImage(cgImage: filtered).pngData() ?? data
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Pre-rendered CDN tiles (fast path).
        if let template = configuration.tileURLTemplate {
            let urlString = template
                .replacingOccurrences(of: "{z}", with: String(path.z))
                .replacingOccurrences(of: "{x}", with: String(path.x))
                .replacingOccurrences(of: "{y}", with: String(path.y))
            if let url = URL(string: urlString) { return url }
        }

        let zoomScale = pow(2.0, Double(path.z))
        let minX = Double(path.x) / zoomScale * worldWidth
        let maxX = Double(path.x + 1) / zoomScale * worldWidth
        let minY = Double(path.y) / zoomScale * worldWidth
        let maxY = Double(path.y + 1) / zoomScale * worldWidth

        let upperLeft = MKMapPoint(x: minX, y: minY).coordinate
        let lowerRight = MKMapPoint(x: maxX, y: maxY).coordinate
        let bbox = [upperLeft.longitude, lowerRight.latitude, lowerRight.longitude, upperLeft.latitude]
            .map { String(format: "%.6f", $0) }
            .joined(separator: ",")

        var components = URLComponents(string: configuration.serviceURL)!
        components.queryItems = [
            URLQueryItem(name: "SERVICE", value: "WMS"),
            URLQueryItem(name: "VERSION", value: "1.1.1"),
            URLQueryItem(name: "REQUEST", value: "GetMap"),
            URLQueryItem(name: "LAYERS", value: configuration.layerName),
            URLQueryItem(name: "STYLES", value: ""),
            URLQueryItem(name: "FORMAT", value: "image/png"),
            URLQueryItem(name: "TRANSPARENT", value: "TRUE"),
            URLQueryItem(name: "SRS", value: "EPSG:4326"),
            URLQueryItem(name: "WIDTH", value: String(Int(tileDimension))),
            URLQueryItem(name: "HEIGHT", value: String(Int(tileDimension))),
            URLQueryItem(name: "BBOX", value: bbox)
        ]

        return components.url!
    }
}

/// Serves IEM archived composite frames for the radar timeline. Tiles are
/// fetched on demand at whatever zoom MapKit asks for (no preload step, so
/// the map never goes blank). RadarTileCache makes frame changes instant
/// after the first fetch — without it every loop pass re-hits the network.
/// `nonisolated` is required: MapKit calls `loadTile` on background queues.
nonisolated final class RidgeTimelineTileOverlay: MKTileOverlay {
    private let lock = NSLock()
    private var _source: RadarFrameSource = .national(minutesAgo: 0)

    /// The imagery this overlay should draw — national mosaic offset or a
    /// single-site RIDGE scan. Read/written from MapKit's background queues.
    var source: RadarFrameSource {
        get { lock.lock(); defer { lock.unlock() }; return _source }
        set { lock.lock(); _source = newValue; lock.unlock() }
    }

    init() {
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping @Sendable (Data?, Error?) -> Void) {
        let source = source
        let cache = RadarTileCache.shared

        if let cached = cache.data(source: source, z: path.z, x: path.x, y: path.y) {
            result(cached, nil)
            return
        }

        guard let url = RadarTileURL.make(source: source, z: path.z, x: path.x, y: path.y) else {
            result(nil, nil)
            return
        }

        NetworkSessions.tiles.dataTask(with: URLRequest(url: url)) { data, response, error in
            if let data,
               let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                cache.store(data, source: source, z: path.z, x: path.x, y: path.y)
                result(data, nil)
            } else {
                result(nil, error)
            }
        }.resume()
    }
}
