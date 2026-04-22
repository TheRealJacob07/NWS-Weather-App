import SwiftUI

struct HourlyStripCell: View {
    let period: HourlyForecastSummary

    // Cached formatters — creating these on every render is expensive
    private static let iso8601 = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()

    var body: some View {
        VStack(spacing: 9) {
            Text(displayTime)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))

            Image(systemName: symbolName)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)

            Text(period.temperature)
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: 58)
        .padding(.vertical, 10)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1, height: 54)
                .offset(x: 6)
        }
    }

    private var displayTime: String {
        guard let date = HourlyStripCell.iso8601.date(from: period.startTime) else {
            return period.name.uppercased().replacingOccurrences(of: " ", with: "")
        }
        return HourlyStripCell.timeFormatter.string(from: date)
    }

    private var symbolName: String {
        let text = period.shortForecast.lowercased()
        if text.contains("storm") || text.contains("thunder") { return "cloud.bolt.fill" }
        if text.contains("snow") || text.contains("sleet") { return "snowflake" }
        if text.contains("rain") || text.contains("showers") { return "cloud.rain.fill" }
        if text.contains("cloud") { return "cloud.fill" }
        if text.contains("night") { return "moon.stars.fill" }
        return "sun.max.fill"
    }
}
