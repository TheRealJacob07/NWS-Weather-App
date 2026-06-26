import SwiftUI

/// EPA AQI gauge card for the home screen.
struct AirQualityCard: View {
    let snapshot: AirQualitySnapshot

    var body: some View {
        WeatherCard(icon: "aqi.medium", title: "Air Quality") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(snapshot.aqi)")
                        .font(.system(size: 38, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(snapshot.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(aqiColor)

                    Spacer()
                }

                // AQI gauge 0–300+
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        LinearGradient(
                            stops: [
                                .init(color: .green, location: 0.0),     // 0–50
                                .init(color: .yellow, location: 0.17),   // 51–100
                                .init(color: .orange, location: 0.34),   // 101–150
                                .init(color: .red, location: 0.5),       // 151–200
                                .init(color: .purple, location: 0.67),   // 201–300
                                .init(color: Color(red: 0.5, green: 0.1, blue: 0.15), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 6)
                        .clipShape(Capsule())
                        .opacity(0.85)

                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                            .offset(x: max(0, geo.size.width * snapshot.gaugeRatio - 6))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 14)

                HStack(spacing: 14) {
                    if let pm25 = snapshot.pm25 {
                        detailStat(label: "PM2.5", value: "\(Int(pm25.rounded())) µg/m³")
                    }
                    if let ozone = snapshot.ozone {
                        detailStat(label: "Ozone", value: "\(Int(ozone.rounded())) µg/m³")
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
    }

    private var aqiColor: Color {
        switch snapshot.aqi {
        case ..<51: return .green
        case ..<101: return .yellow
        case ..<151: return .orange
        case ..<201: return .red
        default: return .purple
        }
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// UV index gauge card.
struct UVIndexCard: View {
    let snapshot: SunSnapshot

    var body: some View {
        WeatherCard(icon: "sun.max.trianglebadge.exclamationmark", title: "UV Index") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(snapshot.uvIndex.rounded()))")
                        .font(.system(size: 38, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(snapshot.uvCategory)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(uvColor)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PEAK TODAY")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.45))
                        Text("\(Int(snapshot.uvMaxToday.rounded()))")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        LinearGradient(
                            stops: [
                                .init(color: .green, location: 0.0),
                                .init(color: .yellow, location: 0.27),
                                .init(color: .orange, location: 0.55),
                                .init(color: .red, location: 0.8),
                                .init(color: .purple, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 6)
                        .clipShape(Capsule())
                        .opacity(0.85)

                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                            .offset(x: max(0, geo.size.width * snapshot.uvGaugeRatio - 6))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 14)

                Text(snapshot.protectionAdvice)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
        }
    }

    private var uvColor: Color {
        switch snapshot.uvIndex {
        case ..<3: return .green
        case ..<6: return .yellow
        case ..<8: return .orange
        case ..<11: return .red
        default: return .purple
        }
    }
}

/// Sunrise/sunset arc with daylight stats and burn-time estimate.
struct SunExposureCard: View {
    let snapshot: SunSnapshot

    var body: some View {
        WeatherCard(icon: "sun.horizon", title: "Sun Exposure") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sunStat(icon: "sunrise.fill", label: "SUNRISE", value: timeText(snapshot.sunrise))
                    Spacer()
                    sunStat(icon: "sunset.fill", label: "SUNSET", value: timeText(snapshot.sunset))
                    Spacer()
                    sunStat(icon: "hourglass", label: "DAYLIGHT", value: snapshot.daylightText)
                }

                // Day progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.12))
                            .frame(height: 5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(5, geo.size.width * snapshot.dayProgress), height: 5)

                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.yellow)
                            .offset(x: max(0, geo.size.width * snapshot.dayProgress - 7), y: 0)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 16)

                Text(snapshot.burnTimeText + " at current UV (fair skin).")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
        }
    }

    private func sunStat(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.yellow.opacity(0.85))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = snapshot.timeZone
        return formatter.string(from: date)
    }
}

/// Pollen / allergen levels card. Shows measured data where available and a
/// clearly-labeled seasonal estimate elsewhere (no free US pollen feed).
struct AllergenCard: View {
    let readings: [PollenReading]
    let isEstimated: Bool

    var body: some View {
        WeatherCard(icon: "allergens", title: "Allergens") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(readings) { reading in
                        VStack(spacing: 6) {
                            Image(systemName: reading.symbolName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(color(for: reading.level))

                            Text(reading.id)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))

                            Text(reading.level.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color(for: reading.level))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(color(for: reading.level).opacity(0.14), in: Capsule(style: .continuous))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if isEstimated {
                    Text("Seasonal estimate from forecast conditions — measured pollen counts aren't published for the US.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(16)
        }
    }

    private func color(for level: PollenLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        }
    }
}
