import Foundation

enum NOAAResource: String, CaseIterable, Identifiable {
    case surfaceAnalysis
    case nationalForecastChart
    case quantitativePrecipitation
    case excessiveRainfall
    case satellite
    case nationalRadar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surfaceAnalysis: return "Surface Analysis"
        case .nationalForecastChart: return "National Forecast Chart"
        case .quantitativePrecipitation: return "QPF Rainfall Outlook"
        case .excessiveRainfall: return "Excessive Rainfall Outlook"
        case .satellite: return "GOES Satellite"
        case .nationalRadar: return "National Radar"
        }
    }

    var subtitle: String {
        switch self {
        case .surfaceAnalysis: return "Fronts, lows, highs, and analyzed surface weather from NOAA WPC."
        case .nationalForecastChart: return "National synoptic forecast maps for the next several days."
        case .quantitativePrecipitation: return "Official NOAA rainfall forecast totals and accumulation maps."
        case .excessiveRainfall: return "WPC flash-flood and excessive rainfall risk outlooks."
        case .satellite: return "NOAA GOES satellite imagery for broad cloud and moisture analysis."
        case .nationalRadar: return "NOAA national radar mosaic for a broader precipitation view."
        }
    }

    var source: String {
        switch self {
        case .satellite: return "NOAA NESDIS"
        case .nationalRadar: return "NOAA NSSL"
        default: return "NOAA WPC"
        }
    }

    var symbolName: String {
        switch self {
        case .surfaceAnalysis: return "point.topleft.down.curvedto.point.bottomright.up"
        case .nationalForecastChart: return "map"
        case .quantitativePrecipitation: return "cloud.rain"
        case .excessiveRainfall: return "exclamationmark.triangle"
        case .satellite: return "globe.americas"
        case .nationalRadar: return "dot.radiowaves.left.and.right"
        }
    }

    var url: URL {
        switch self {
        case .surfaceAnalysis:
            return URL(string: "https://www.wpc.ncep.noaa.gov/html/sfc-zoom.php")!
        case .nationalForecastChart:
            return URL(string: "https://www.wpc.ncep.noaa.gov/basicwx/basicwx_ndfd.php")!
        case .quantitativePrecipitation:
            return URL(string: "https://www.wpc.ncep.noaa.gov/qpf/day1-7.shtml")!
        case .excessiveRainfall:
            return URL(string: "https://www.wpc.ncep.noaa.gov/#page=ero")!
        case .satellite:
            return URL(string: "https://www.star.nesdis.noaa.gov/GOES/")!
        case .nationalRadar:
            return URL(string: "https://radar.weather.gov/")!
        }
    }
}
