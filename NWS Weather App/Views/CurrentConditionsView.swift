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

            SectionCard(title: "Quick Read", subtitle: "Latest local snapshot") {
                VStack(spacing: 12) {
                    InsightRow(label: "Temperature", value: forecast?.temperature ?? "--")
                    InsightRow(label: "Humidity", value: observation?.humidity ?? "--")
                    InsightRow(label: "Wind Speed", value: observation?.wind ?? "--")
                    InsightRow(label: "Barometer", value: observation?.barometer ?? "--")
                    InsightRow(label: "Dewpoint", value: observation?.dewpoint ?? "--")
                    InsightRow(label: "Visibility", value: observation?.visibility ?? "--")
                    InsightRow(label: "Last Update", value: observation?.lastUpdate ?? "--")
                }
            }
        }
    }
}
