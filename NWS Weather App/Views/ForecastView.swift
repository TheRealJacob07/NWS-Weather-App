import SwiftUI

struct ForecastView: View {
    let periods: [ForecastPeriodSummary]

    var body: some View {
        if !periods.isEmpty {
            VStack(spacing: 10) {
                ForEach(periods) { period in
                    ForecastPeriodRow(period: period)
                }
            }
        }
    }
}
