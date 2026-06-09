import SwiftUI

/// Apple Weather-style section card: a Liquid Glass slab with a small
/// uppercase caption header, divider, and arbitrary content.
struct WeatherCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.05)), in: .rect(cornerRadius: 22))
    }
}

/// Square statistic tile used in the conditions grid.
struct ConditionTile<Detail: View>: View {
    let icon: String
    let title: String
    let value: String
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(.white.opacity(0.6))

            Text(value)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 10)

            Spacer(minLength: 4)

            detail
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .glassEffect(.regular.tint(.white.opacity(0.05)), in: .rect(cornerRadius: 22))
    }
}

extension ConditionTile where Detail == Text {
    init(icon: String, title: String, value: String, detailText: String) {
        self.init(icon: icon, title: title, value: value) {
            Text(detailText)
        }
    }
}
