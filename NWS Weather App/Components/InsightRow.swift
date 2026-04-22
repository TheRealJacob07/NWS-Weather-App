import SwiftUI

struct InsightRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))

            Spacer(minLength: 16)

            Text(value)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
