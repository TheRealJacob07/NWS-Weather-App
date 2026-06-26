import Foundation

/// One selectable frame inside a NOAA product (e.g. "Day 2" of the
/// national forecast chart). All URLs are direct image products published
/// by NOAA centers, so everything renders natively in the app.
struct NOAAProductFrame: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: String { url.absoluteString }
}

enum NOAAResource: String, CaseIterable, Identifiable {
    case surfaceAnalysis
    case nationalForecastChart
    case quantitativePrecipitation
    case excessiveRainfall
    case severeOutlook
    case satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surfaceAnalysis: return "Surface Analysis"
        case .nationalForecastChart: return "Forecast Chart"
        case .quantitativePrecipitation: return "Rainfall Forecast"
        case .excessiveRainfall: return "Flash Flood Risk"
        case .severeOutlook: return "Severe Outlook"
        case .satellite: return "GOES Satellite"
        }
    }

    var subtitle: String {
        switch self {
        case .surfaceAnalysis: return "Fronts, highs, and lows analyzed by NOAA WPC."
        case .nationalForecastChart: return "National synoptic forecast for the next 3 days."
        case .quantitativePrecipitation: return "Official rainfall totals through 5 days."
        case .excessiveRainfall: return "WPC excessive rainfall & flash-flood outlooks."
        case .severeOutlook: return "SPC severe thunderstorm outlooks, days 1–3."
        case .satellite: return "Live GOES East & West GeoColor imagery."
        }
    }

    var source: String {
        switch self {
        case .satellite: return "NOAA NESDIS"
        case .severeOutlook: return "NOAA SPC"
        default: return "NOAA WPC"
        }
    }

    var symbolName: String {
        switch self {
        case .surfaceAnalysis: return "point.topleft.down.curvedto.point.bottomright.up"
        case .nationalForecastChart: return "map"
        case .quantitativePrecipitation: return "cloud.rain"
        case .excessiveRainfall: return "exclamationmark.triangle"
        case .severeOutlook: return "tornado"
        case .satellite: return "globe.americas"
        }
    }

    /// Direct image frames, shown with a frame picker in the native viewer.
    var frames: [NOAAProductFrame] {
        switch self {
        case .surfaceAnalysis:
            return [
                NOAAProductFrame(title: "Current", url: URL(string: "https://www.wpc.ncep.noaa.gov/sfc/namussfcwbg.gif")!)
            ]
        case .nationalForecastChart:
            return [
                NOAAProductFrame(title: "Day 1", url: URL(string: "https://www.wpc.ncep.noaa.gov/noaa/noaad1.gif")!),
                NOAAProductFrame(title: "Day 2", url: URL(string: "https://www.wpc.ncep.noaa.gov/noaa/noaad2.gif")!),
                NOAAProductFrame(title: "Day 3", url: URL(string: "https://www.wpc.ncep.noaa.gov/noaa/noaad3.gif")!)
            ]
        case .quantitativePrecipitation:
            return [
                NOAAProductFrame(title: "Day 1", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/94qwbg.gif")!),
                NOAAProductFrame(title: "Day 2", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/98qwbg.gif")!),
                NOAAProductFrame(title: "Day 3", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/99qwbg.gif")!),
                NOAAProductFrame(title: "5-Day", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/p120i.gif")!)
            ]
        case .excessiveRainfall:
            return [
                NOAAProductFrame(title: "Day 1", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/94ewbg.gif")!),
                NOAAProductFrame(title: "Day 2", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/98ewbg.gif")!),
                NOAAProductFrame(title: "Day 3", url: URL(string: "https://www.wpc.ncep.noaa.gov/qpf/99ewbg.gif")!)
            ]
        case .severeOutlook:
            return [
                NOAAProductFrame(title: "Day 1", url: URL(string: "https://www.spc.noaa.gov/products/outlook/day1otlk.png")!),
                NOAAProductFrame(title: "Day 2", url: URL(string: "https://www.spc.noaa.gov/products/outlook/day2otlk.png")!),
                NOAAProductFrame(title: "Day 3", url: URL(string: "https://www.spc.noaa.gov/products/outlook/day3otlk.png")!)
            ]
        case .satellite:
            return [
                NOAAProductFrame(title: "East", url: URL(string: "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/CONUS/GEOCOLOR/1250x750.jpg")!),
                NOAAProductFrame(title: "West", url: URL(string: "https://cdn.star.nesdis.noaa.gov/GOES18/ABI/CONUS/GEOCOLOR/1250x750.jpg")!)
            ]
        }
    }

    /// Satellite frames update every ~5 minutes; cache-bust on refresh.
    var refreshesFrequently: Bool { self == .satellite }
}
