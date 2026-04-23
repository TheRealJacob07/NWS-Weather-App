import SwiftUI

struct ForecastPeriodRow: View {
    let period: ForecastPeriodSummary

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(period.name)
                    .font(.headline)
                Text(period.shortForecast)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(period.temperature)
                    .font(.title2.weight(.semibold))
                Text(period.wind)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.trailing)
                Text(period.rain)
                    .font(.caption)
                    .foregroundStyle(.cyan.opacity(0.72))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    private var symbolName: String {
        let text = period.shortForecast.lowercased()
        let isNight = period.name.lowercased().contains("night")
        if text.contains("storm") || text.contains("thunder") { return "cloud.bolt.fill" }
        if text.contains("snow") || text.contains("sleet") { return "snowflake" }
        if text.contains("rain") || text.contains("shower") { return "cloud.rain.fill" }
        if text.contains("drizzle") { return "cloud.drizzle.fill" }
        if text.contains("fog") { return "cloud.fog.fill" }
        if text.contains("partly") || text.contains("mostly cloudy") {
            return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        }
        if text.contains("cloud") || text.contains("overcast") { return "cloud.fill" }
        return isNight ? "moon.stars.fill" : "sun.max.fill"
    }
}
