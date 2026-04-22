enum WeatherPage: String, CaseIterable, Identifiable {
    case current
    case forecast
    case radar
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: return "Now"
        case .forecast: return "Forecast"
        case .radar: return "Radar"
        case .tools: return "Tools"
        }
    }

    var symbolName: String {
        switch self {
        case .current: return "sun.max.fill"
        case .forecast: return "calendar"
        case .radar: return "dot.radiowaves.left.and.right"
        case .tools: return "square.grid.2x2.fill"
        }
    }
}
