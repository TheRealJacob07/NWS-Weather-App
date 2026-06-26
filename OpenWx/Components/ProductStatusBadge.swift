import SwiftUI

struct ProductStatusBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.cyan.opacity(0.85))

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        }
    }
}
