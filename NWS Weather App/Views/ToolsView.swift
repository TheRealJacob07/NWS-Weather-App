import SwiftUI

/// NWS resources and app status, presented as a sheet from the bottom bar menu.
struct ToolsView: View {
    let statusMessage: String
    let activeLocationStatus: String
    let savedLocationCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMapResource: NOAAResource?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))
            .navigationTitle("NWS Resources")
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
