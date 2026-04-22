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

        if let selectedRadarSiteID,
           let annotation = annotations.first(where: { $0.site.radarID == selectedRadarSiteID }) {
            mapView.selectAnnotation(annotation, animated: true)
        }
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
        var radarOverlay: NWSRadarTileOverlay?
        var lastCoordinate: CLLocationCoordinate2D?
        var lastSpanDelta: Double?
        var radarSiteAnnotations: [RadarSiteAnnotation] = []
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
            guard let annotation = annotation as? RadarSiteAnnotation else { return nil }

            let identifier = "RadarSiteBeacon"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = annotation.site.radarID == selectedRadarSiteID
                ? .systemTeal
                : UIColor(red: 0.15, green: 0.58, blue: 1.0, alpha: 1.0)
            view.glyphText = annotation.site.radarID
            view.glyphTintColor = .white
            view.titleVisibility = .visible
            view.subtitleVisibility = .visible
            view.displayPriority = .defaultHigh
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? RadarSiteAnnotation else { return }
            selectedRadarSiteID = annotation.site.radarID
            onSelectRadarSite(annotation.site)
        }
    }
}

private final class RadarSiteAnnotation: NSObject, MKAnnotation {
    let site: RadarSite
    var coordinate: CLLocationCoordinate2D { site.coordinate }
    var title: String? { site.name }
    var subtitle: String? { site.radarID }

    init(site: RadarSite) {
        self.site = site
    }
}

private final class NWSRadarTileOverlay: MKTileOverlay {
    let configuration: RadarLayerConfiguration
    private let tileDimension = 256.0
    private let worldWidth = MKMapSize.world.width

    init(configuration: RadarLayerConfiguration) {
        self.configuration = configuration
        super.init(urlTemplate: nil)
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
