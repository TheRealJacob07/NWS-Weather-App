import SwiftUI

struct CurrentConditionsView: View {
    let forecast: ForecastSummary?
    let observation: CurrentObservationSummary?
    let hourlyPeriods: [HourlyForecastSummary]

    var body: some View {
        VStack(spacing: 20) {
            if !hourlyPeriods.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(hourlyPeriods) { period in
                            HourlyStripCell(period: period)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.blue.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.08))
                        }
                )
                .glassEffect(.regular.tint(.blue.opacity(0.18)), in: .rect(cornerRadius: 26))
            }

            if let obs = observation {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ConditionTile(icon: "humidity", label: "Humidity", value: obs.humidity)
                    ConditionTile(icon: "wind", label: "Wind", value: obs.wind)
                    ConditionTile(icon: "gauge.medium", label: "Pressure", value: obs.barometer)
                    ConditionTile(icon: "thermometer.medium", label: "Dewpoint", value: obs.dewpoint)
                    ConditionTile(icon: "eye", label: "Visibility", value: obs.visibility)
                    ConditionTile(icon: "clock", label: "Updated", value: obs.lastUpdate)
                }
            }
        }
    }
}

private struct ConditionTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }
}
