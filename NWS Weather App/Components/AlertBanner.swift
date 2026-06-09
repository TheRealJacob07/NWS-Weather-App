import SwiftUI

/// Tappable active-alert banner shown above the hourly forecast,
/// like Apple Weather's severe weather card.
struct AlertBanner: View {
    let alert: WeatherAlertSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.event)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(alert.endsText ?? alert.headline)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(severityColor.opacity(0.55)).interactive(), in: .rect(cornerRadius: 22))
    }

    private var severityColor: Color {
        switch alert.severity {
        case .extreme: return .red
        case .severe: return .red
        case .moderate: return .orange
        case .minor: return .yellow
        case .unknown: return .orange
        }
    }
}

/// Full alert text presented as a sheet.
struct AlertDetailSheet: View {
    let alert: WeatherAlertSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(alert.headline)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let endsText = alert.endsText {
                        Label(endsText, systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    Text(alert.details)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))

                    if let instruction = alert.instruction, !instruction.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("INSTRUCTIONS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(instruction)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Text("Source: National Weather Service")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(20)
            }
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))
            .navigationTitle(alert.event)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
