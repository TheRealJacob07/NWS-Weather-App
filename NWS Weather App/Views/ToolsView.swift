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
            SectionCard(title: "Status") {
                VStack(spacing: 12) {
                    InsightRow(label: "Weather", value: statusMessage)
                    InsightRow(label: "Location", value: activeLocationStatus)
                    InsightRow(label: "Saved Places", value: "\(savedLocationCount)")
                }
            }

            SectionCard(title: "NOAA Resources", subtitle: "Official forecast and analysis products") {
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
}
