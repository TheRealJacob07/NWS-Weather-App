import MapKit
import SwiftUI

struct RadarMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D?
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let radarSites: [RadarSite]
    let selectedRadarSiteID: String?
    let showsRadarSites: Bool
    let stormTracks: [StormTrack]
    let onSelectRadarSite: (RadarSite) -> Void
    let configuration: RadarLayerConfiguration?
    let spanDelta: Double

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

        updateOverlay(on: mapView, coordinator: context.coordinator)
        updateStormTrackOverlays(on: mapView, coordinator: context.coordinator)
        updateRadarSiteAnnotations(on: mapView, coordinator: context.coordinator)
        setVisibleRegion(on: mapView, coordinator: context.coordinator, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateOverlay(on: mapView, coordinator: context.coordinator)
        updateStormTrackOverlays(on: mapView, coordinator: context.coordinator)
        updateRadarSiteAnnotations(on: mapView, coordinator: context.coordinator)
        setVisibleRegion(on: mapView, coordinator: context.coordinator, animated: true)
    }

    private func updateOverlay(on mapView: MKMapView, coordinator: Coordinator) {
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

    private func updateStormTrackOverlays(on mapView: MKMapView, coordinator: Coordinator) {
        let trackIDs = stormTracks.map(\.id)
        guard coordinator.stormTrackIDs != trackIDs else { return }

        if !coordinator.stormTrackOverlays.isEmpty {
            mapView.removeOverlays(coordinator.stormTrackOverlays)
            coordinator.stormTrackOverlays.removeAll()
        }

        let overlays = stormTracks.map { track in
            let polyline = MKPolyline(coordinates: track.coordinates, count: track.coordinates.count)
            polyline.title = track.style.rawValue
            return polyline
        }
        mapView.addOverlays(overlays, level: .aboveLabels)
        coordinator.stormTrackOverlays = overlays
        coordinator.stormTrackIDs = trackIDs
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

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onSelectRadarSite: (RadarSite) -> Void
        var currentConfiguration: RadarLayerConfiguration?
        fileprivate var radarOverlay: NWSRadarTileOverlay?
        var lastCoordinate: CLLocationCoordinate2D?
        var lastSpanDelta: Double?
        fileprivate var radarSiteAnnotations: [RadarSiteAnnotation] = []
        var radarSiteIDs: [String] = []
        var selectedRadarSiteID: String?
        var stormTrackOverlays: [MKPolyline] = []
        var stormTrackIDs: [UUID] = []

        init(onSelectRadarSite: @escaping (RadarSite) -> Void) {
            self.onSelectRadarSite = onSelectRadarSite
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let isWarning = polyline.title == StormTrackStyle.warningArea.rawValue
                renderer.lineWidth = isWarning ? 3 : 4
                renderer.strokeColor = isWarning
                    ? UIColor.systemOrange.withAlphaComponent(0.85)
                    : UIColor.systemPink.withAlphaComponent(0.92)
                if isWarning { renderer.lineDashPattern = [8, 6] }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

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

    /// NOAA RIDGE2 reflectivity color curve, sampled from the official
    /// GetLegendGraphic for the sr_bref product. 40 stops spanning
    /// -30 dBZ (index 0) to +75 dBZ in 2.625 dBZ steps.
    private static let reflectivityPalette: [(UInt8, UInt8, UInt8)] = [
        (143, 133, 116), (147, 140, 94), (157, 153, 95), (171, 169, 118),
        (186, 186, 143), (201, 203, 167), (201, 204, 180), (185, 190, 180),
        (168, 175, 180), (155, 162, 180), (135, 145, 177), (112, 127, 171),
        (90, 111, 165), (75, 100, 161), (74, 114, 171), (87, 152, 194),
        (90, 183, 195), (85, 203, 173), (64, 214, 125), (32, 214, 57),
        (13, 193, 18), (11, 156, 16), (10, 125, 13), (9, 105, 10),
        (73, 128, 6), (191, 191, 2), (249, 214, 12), (239, 191, 34),
        (239, 178, 34), (249, 177, 11), (231, 4, 4), (186, 12, 12),
        (165, 11, 12), (173, 4, 4), (248, 219, 254), (234, 152, 253),
        (234, 116, 252), (247, 116, 254), (150, 0, 241), (110, 0, 221)
    ]

    init(configuration: RadarLayerConfiguration) {
        self.configuration = configuration
        self.minimumDBZ = configuration.minimumDBZ
        super.init(urlTemplate: nil)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        guard let minimumDBZ else {
            super.loadTile(at: path, result: result)
            return
        }

        var request = URLRequest(url: url(forTilePath: path))
        request.setValue("NWS Weather App (jacob@example.com)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
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
            let r = Double(r5 << 3 | r5 >> 2)
            for g5 in 0..<32 {
                let g = Double(g5 << 3 | g5 >> 2)
                for b5 in 0..<32 {
                    let b = Double(b5 << 3 | b5 >> 2)

                    var bestIndex = 0
                    var bestDistance = Double.greatestFiniteMagnitude
                    for (index, color) in reflectivityPalette.enumerated() {
                        let dr = r - Double(color.0)
                        let dg = g - Double(color.1)
                        let db = b - Double(color.2)
                        let distance = dr * dr + dg * dg + db * db
                        if distance < bestDistance {
                            bestDistance = distance
                            bestIndex = index
                        }
                    }

                    let dbz = -30.0 + Double(bestIndex) * 2.625
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
