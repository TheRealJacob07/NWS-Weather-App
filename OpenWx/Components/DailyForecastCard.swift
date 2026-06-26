import SwiftUI

/// 7-day forecast card with Apple Weather-style temperature range bars.
struct DailyForecastCard: View {
    let days: [DailyForecastSummary]

    private var weekLow: Int {
        days.compactMap { min($0.low ?? Int.max, $0.high ?? Int.max) }.min() ?? 0
    }

    private var weekHigh: Int {
        days.compactMap { max($0.high ?? Int.min, $0.low ?? Int.min) }.max() ?? 1
    }

    var body: some View {
        WeatherCard(icon: "calendar", title: "7-Day Forecast") {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    DailyRow(day: day, weekLow: weekLow, weekHigh: weekHigh)

                    if index < days.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DailyRow: View {
    let day: DailyForecastSummary
    let weekLow: Int
    let weekHigh: Int

    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text(day.dayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 58, alignment: .leading)

                    VStack(spacing: 0) {
                        WeatherSymbol.image(for: day.shortForecast, isDaytime: day.isDaytime)
                            .font(.system(size: 18))

                        if day.precipChance >= 10 {
                            Text("\(day.precipChance)%")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.cyan)
                        }
                    }
                    .frame(width: 44)

                    Text(day.low.map { "\($0)°" } ?? "--")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 38, alignment: .trailing)

                    TemperatureRangeBar(
                        low: day.low ?? day.high ?? weekLow,
                        high: day.high ?? day.low ?? weekHigh,
                        rangeLow: weekLow,
                        rangeHigh: weekHigh
                    )

                    Text(day.high.map { "\($0)°" } ?? "--")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 38, alignment: .trailing)
                }

                if isExpanded && !day.detailedForecast.isEmpty {
                    Text(day.detailedForecast)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The gradient capsule showing where a day's range sits within the week.
struct TemperatureRangeBar: View {
    let low: Int
    let high: Int
    let rangeLow: Int
    let rangeHigh: Int

    var body: some View {
        GeometryReader { geometry in
            let span = max(1, rangeHigh - rangeLow)
            let start = CGFloat(max(0, low - rangeLow)) / CGFloat(span)
            let end = CGFloat(max(0, min(high, rangeHigh) - rangeLow)) / CGFloat(span)
            let width = max(geometry.size.width * (end - start), 6)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.25))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                TemperatureColor.color(for: low),
                                TemperatureColor.color(for: high)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .offset(x: min(geometry.size.width * start, geometry.size.width - width))
            }
        }
        .frame(height: 5)
    }
}
