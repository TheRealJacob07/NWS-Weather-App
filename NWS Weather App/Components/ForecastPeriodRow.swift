import SwiftUI

struct ForecastPeriodRow: View {
    let period: ForecastPeriodSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(period.name)
                    .font(.headline)
                Text(period.shortForecast)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(period.temperature)
                    .font(.title3.weight(.semibold))
                Text(period.wind)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.trailing)
                Text(period.rain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
