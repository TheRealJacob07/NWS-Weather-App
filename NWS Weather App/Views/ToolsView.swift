import SwiftUI

struct ToolsView: View {
    let forecast: ForecastSummary?
    let periods: [ForecastPeriodSummary]
    let latitude: Double?
    let longitude: Double?
    let statusMessage: String
    let activeLocationStatus: String
    let savedLocationCount: Int

    @State private var selectedMapResource: NOAAResource?

    var body: some View {
        VStack(spacing: 16) {
            SectionCard(title: "Meteorology Tools", subtitle: "Operational context for the active location") {
                VStack(spacing: 12) {
                    InsightRow(label: "Forecast", value: forecast?.shortForecast ?? "--")
                    InsightRow(label: "Temperature", value: forecast?.temperature ?? "--")
                    InsightRow(label: "Wind", value: forecast?.wind ?? "--")
                    InsightRow(label: "Rain", value: forecast?.rain ?? "--")
                    InsightRow(label: "Location", value: locationLine)
                }
            }

            SectionCard(title: "Coordinates", subtitle: "Pinned to the active weather target") {
                VStack(spacing: 12) {
                    InsightRow(label: "Latitude", value: coordinateString(latitude))
                    InsightRow(label: "Longitude", value: coordinateString(longitude))
                }
            }

            SectionCard(title: "System", subtitle: "Load status and tools context") {
                VStack(spacing: 12) {
                    InsightRow(label: "Weather", value: statusMessage)
                    InsightRow(label: "Location", value: activeLocationStatus)
                    InsightRow(label: "Saved Places", value: "\(savedLocationCount)")
                    InsightRow(label: "Periods", value: "\(periods.count)")
                }
            }

            SectionCard(title: "NOAA Maps", subtitle: "Open official forecast and analysis products in-app") {
                VStack(spacing: 12) {
                    ForEach(NOAAResource.allCases) { resource in
                        Button {
                            selectedMapResource = resource
                        } label: {
                            NOAAResourceRow(resource: resource)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedMapResource) { resource in
            NOAAResourceBrowser(resource: resource)
        }
    }

    private var locationLine: String {
        guard let forecast else { return "--" }
        return "\(forecast.locationName), \(forecast.state)"
    }

    private func coordinateString(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(4)))
    }
}
