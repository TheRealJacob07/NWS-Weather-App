import SwiftUI

struct ForecastView: View {
    let periods: [ForecastPeriodSummary]

    var body: some View {
        VStack(spacing: 16) {
            SectionCard(title: "Forecast Timeline", subtitle: "Upcoming National Weather Service periods") {
                if periods.isEmpty {
                    Text("No forecast periods loaded yet.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    VStack(spacing: 12) {
                        ForEach(periods) { period in
                            ForecastPeriodRow(period: period)
                        }
                    }
                }
            }
        }
    }
}
