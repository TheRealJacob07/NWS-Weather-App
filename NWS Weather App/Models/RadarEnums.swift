import CoreLocation

enum RadarScope: String, CaseIterable, Identifiable {
    case local
    case national

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local"
        case .national: return "National"
        }
    }

    var description: String {
        switch self {
        case .local: return "The map is centered on your selected location."
        case .national: return "The map is zoomed out to show the broader national rain pattern."
        }
    }
}

enum RadarProduct: String, CaseIterable, Identifiable {
    case compositeReflectivity
    case baseReflectivity
    case echoTops
    case nationalRain
    case velocity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compositeReflectivity: return "Composite"
        case .baseReflectivity: return "Base Refl"
        case .echoTops: return "Echo Tops"
        case .nationalRain: return "National Rain"
        case .velocity: return "Velocity"
        }
    }

    var shortTitle: String {
        switch self {
        case .compositeReflectivity: return "CREF"
        case .baseReflectivity: return "BREF"
        case .echoTops: return "ETOPS"
        case .nationalRain: return "RAIN"
        case .velocity: return "VEL"
        }
    }

    var description: String {
        switch self {
        case .compositeReflectivity:
            return "Composite reflectivity from NOAA's MRMS mosaic gives a broad storm view across the selected region."
        case .baseReflectivity:
            return "Base reflectivity emphasizes lower-level returns and keeps the view on official NOAA regional radar mosaics."
        case .echoTops:
            return "Echo tops highlight storm height and intensity using the NOAA NEET product."
        case .nationalRain:
            return "National rain uses NOAA's composite reflectivity mosaic so active precipitation is visible across the country."
        case .velocity:
            return "Velocity uses the nearest radar site feed to show inbound and outbound winds relative to that radar."
        }
    }

    var supportsScopeSelection: Bool {
        self != .velocity
    }

    /// Noise filtering only applies to raw single-site reflectivity feeds.
    /// The regional/national mosaics (QCD) are already quality-controlled.
    func supportsNoiseFilter(scope: RadarScope) -> Bool {
        scope == .local && (self == .compositeReflectivity || self == .baseReflectivity)
    }

    func configuration(
        for coordinate: CLLocationCoordinate2D?,
        scope: RadarScope,
        nearestSite: RadarSite?,
        noiseFilter: RadarNoiseFilter = .off
    ) -> RadarLayerConfiguration? {
        switch self {
        case .compositeReflectivity, .baseReflectivity:
            if scope == .local, let nearestSite {
                let key = nearestSite.radarID.lowercased()
                return RadarLayerConfiguration(
                    serviceURL: "https://opengeo.ncep.noaa.gov/geoserver/\(key)/ows",
                    layerName: nearestSite.reflectivityLayerName,
                    sourceLabel: nearestSite.radarID,
                    minimumDBZ: noiseFilter.minimumDBZ
                )
            }
            let domain = RadarDomain.domain(for: coordinate)
            let product = self == .compositeReflectivity ? "cref_qcd" : "bref_qcd"
            return RadarLayerConfiguration(
                serviceURL: "https://opengeo.ncep.noaa.gov/geoserver/\(domain.pathComponent)/\(domain.pathComponent)_\(product)/ows",
                layerName: "\(domain.pathComponent)_\(product)",
                sourceLabel: domain.shortSourceLabel
            )
        case .echoTops:
            let domain = RadarDomain.domain(for: coordinate)
            return RadarLayerConfiguration(
                serviceURL: "https://opengeo.ncep.noaa.gov/geoserver/\(domain.pathComponent)/\(domain.pathComponent)_neet_v18/ows",
                layerName: "\(domain.pathComponent)_neet_v18",
                sourceLabel: domain.shortSourceLabel
            )
        case .nationalRain:
            return RadarLayerConfiguration(
                serviceURL: "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_cref_qcd/ows",
                layerName: "conus_cref_qcd",
                sourceLabel: "NOAA CONUS"
            )
        case .velocity:
            guard let nearestSite else { return nil }
            let key = nearestSite.radarID.lowercased()
            return RadarLayerConfiguration(
                serviceURL: "https://opengeo.ncep.noaa.gov/geoserver/\(key)/ows",
                layerName: nearestSite.velocityLayerName,
                sourceLabel: nearestSite.radarID
            )
        }
    }
}

/// RadarScope-style clutter filter. Pixels whose palette color maps to
/// reflectivity below the threshold are removed from single-site tiles.
enum RadarNoiseFilter: String, CaseIterable, Identifiable {
    case off
    case light
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .strong: return "Strong"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Show the raw radar feed"
        case .light: return "Hide returns below 10 dBZ"
        case .strong: return "Hide returns below 20 dBZ"
        }
    }

    var minimumDBZ: Double? {
        switch self {
        case .off: return nil
        case .light: return 10
        case .strong: return 20
        }
    }
}

enum RadarDomain {
    case conus, alaska, hawaii, caribbean, guam

    var pathComponent: String {
        switch self {
        case .conus: return "conus"
        case .alaska: return "alaska"
        case .hawaii: return "hawaii"
        case .caribbean: return "carib"
        case .guam: return "guam"
        }
    }

    var title: String {
        switch self {
        case .conus: return "CONUS"
        case .alaska: return "Alaska"
        case .hawaii: return "Hawaii"
        case .caribbean: return "Caribbean"
        case .guam: return "Guam"
        }
    }

    var shortSourceLabel: String { "NOAA \(title)" }

    static func domain(for coordinate: CLLocationCoordinate2D?) -> RadarDomain {
        guard let coordinate else { return .conus }
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        if lat > 50 || lon < -130 { return .alaska }
        if (18...23).contains(lat), (-161 ... -154).contains(lon) { return .hawaii }
        if (16...20).contains(lat), (-68 ... -63).contains(lon) { return .caribbean }
        if (13...15.5).contains(lat), (143...146).contains(lon) { return .guam }
        return .conus
    }
}
