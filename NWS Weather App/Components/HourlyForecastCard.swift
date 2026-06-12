import SwiftUI

/// Horizontally scrolling 24-hour forecast card, styled after Apple Weather.
struct HourlyForecastCard: View {
    let periods: [HourlyForecastSummary]
    var summaryText: String?

    var body: some View {
        WeatherCard(icon: "clock", title: "Hourly Forecast") {
            VStack(alignment: .leading, spacing: 0) {

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(periods) { period in
                            HourlyCell(period: period)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct HourlyCell: View {
    let period: HourlyForecastSummary

    var body: some View {
        VStack(spacing: 0) {
            Text(period.timeLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(period.timeLabel == "Now" ? 1 : 0.85))

            VStack(spacing: 1) {
                WeatherSymbol.image(for: period.shortForecast, isDaytime: period.isDaytime)
                    .font(.system(size: 20))
                    .frame(height: 26)

                if period.precipChance >= 10 {
                    Text("\(period.precipChance)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.cyan)
                } else {
                    Text(" ")
                        .font(.caption2.weight(.semibold))
                }
            }
            .padding(.top, 8)

            Text(period.temperatureText)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 4)
        }
        .frame(width: 60)
        .padding(.vertical, 10)
    }
}
