import SwiftUI

/// NOAA forecast centers' products rendered natively, plus app status —
/// presented as a sheet from the bottom bar menu.
struct ToolsView: View {
    let statusMessage: String
    let activeLocationStatus: String
    let savedLocationCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMapResource: NOAAResource?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.11),
                        Color(red: 0.03, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        SectionCard(title: "Forecast Centers", subtitle: "Official NOAA analysis — rendered right here, no browser") {
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

                        SectionCard(title: "Status") {
                            VStack(spacing: 12) {
                                InsightRow(label: "Weather", value: statusMessage)
                                InsightRow(label: "Location", value: activeLocationStatus)
                                InsightRow(label: "Saved Places", value: "\(savedLocationCount)")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("NWS Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedMapResource) { resource in
                NOAAResourceBrowser(resource: resource)
            }
        }
        .preferredColorScheme(.dark)
    }
}
