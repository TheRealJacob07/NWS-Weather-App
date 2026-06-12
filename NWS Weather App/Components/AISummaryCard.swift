import SwiftUI

/// Apple Intelligence weather briefing card shown on the home screen.
/// Streams an on-device generated summary and opens the chat sheet.
struct AISummaryCard: View {
    @ObservedObject var intelligence: WeatherIntelligenceService
    let onOpenChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("AI BRIEFING")
                    .font(.footnote.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Text("On-device")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.07), in: Capsule(style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                switch intelligence.availability {
                case .available:
                    if intelligence.summary.isEmpty && intelligence.isSummarizing {
                        thinkingPlaceholder
                    } else if intelligence.summary.isEmpty {
                        Text("Your AI weather briefing will appear here once the forecast loads.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        Text(intelligence.summary)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineSpacing(3)
                            .contentTransition(.opacity)
                    }

                    Button(action: onOpenChat) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.caption.weight(.semibold))
                            Text("Ask about the weather")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.cyan.opacity(0.16)).interactive(), in: .capsule)

                case .unavailable(let reason):
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineSpacing(3)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.05)), in: .rect(cornerRadius: 22))
    }

    private var thinkingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(0.8)
            Text("Reading the forecast…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
