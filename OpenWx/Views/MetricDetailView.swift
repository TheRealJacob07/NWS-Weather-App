import Charts
import SwiftUI

/// A condition tile flips into this centered, scrubbable card — the Apple
/// Weather "tap a tile to see the next 24 hours" interaction. The card sizes
/// to its content rather than filling the screen, and uses a solid frosted
/// background so chart colors never bleed past its edges. Drag across the
/// chart to inspect any hour.
struct MetricDetailView: View {
    let metric: WeatherMetric
    let points: [MetricPoint]
    /// The current reading shown in the header (from the live observation).
    let currentText: String
    let onClose: () -> Void

    @State private var selectedDate: Date?

    private var selectedPoint: MetricPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if points.count >= 2 {
                chart
                    .frame(height: 200)
                    // Clip the area fill to the chart's own frame — Swift Charts
                    // lets the AreaMark spill below the axis otherwise, which
                    // looked like orange bleeding into the summary.
                    .clipped()
                    .padding(.top, 22)

                summary
                    .padding(.top, 22)
            } else {
                Text("Hourly trend isn't available right now.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        // Fully opaque so the warm weather background behind the card can't
        // show through and look like the chart is bleeding down the screen.
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .padding(.horizontal, 16)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(metric.title.uppercased(), systemImage: metric.icon)
                    .font(.footnote.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(metric.tint)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(9)
                        .background(.white.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
            }

            Text(selectedPoint.map { metric.format($0.value) } ?? currentText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: selectedPoint)

            Text(selectedPoint.map { headerSubtitle(for: $0) } ?? metric.caption)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func headerSubtitle(for point: MetricPoint) -> String {
        point.date.formatted(.dateTime.weekday(.abbreviated).hour())
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ForEach(Array(summaryStats.enumerated()), id: \.offset) { index, stat in
                    VStack(spacing: 4) {
                        Text(stat.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(0.4)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(stat.value)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    if index < summaryStats.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 0.5, height: 30)
                    }
                }
            }

            Text(summarySentence)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 20))
    }

    private var summaryStats: [(label: String, value: String)] {
        let values = points.map(\.value)
        guard let lo = values.min(), let hi = values.max(), !values.isEmpty else { return [] }
        let avg = values.reduce(0, +) / Double(values.count)
        return [
            ("Low", metric.format(lo)),
            ("Average", metric.format(avg)),
            ("High", metric.format(hi))
        ]
    }

    private var summarySentence: String {
        guard
            let maxPoint = points.max(by: { $0.value < $1.value }),
            let minPoint = points.min(by: { $0.value < $1.value })
        else { return metric.caption }
        let peakTime = maxPoint.date.formatted(.dateTime.hour())
        switch metric.kind {
        case .temperature:
            return "Climbs to \(metric.format(maxPoint.value)) around \(peakTime), dipping to \(metric.format(minPoint.value)) at its coolest."
        case .humidity:
            return "Humidity ranges from \(metric.format(minPoint.value)) to \(metric.format(maxPoint.value)) over the next 24 hours."
        case .wind:
            return "Winds peak near \(metric.format(maxPoint.value)) around \(peakTime)."
        case .precipitation:
            if maxPoint.value < 5 {
                return "Little to no precipitation expected over the next 24 hours."
            }
            return "Highest chance of precipitation is \(metric.format(maxPoint.value)) around \(peakTime)."
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                marks(for: point)
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        Text(metric.format(selected.value))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(metric.tint.opacity(0.9), in: .capsule)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: yDomain)
        // Clip marks to the plot area so the area fill stops at the axis line
        // and never reaches down into the time labels below it.
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.07))
                AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.07))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    @ChartContentBuilder
    private func marks(for point: MetricPoint) -> some ChartContent {
        switch metric.style {
        case .area:
            AreaMark(
                x: .value("Time", point.date),
                y: .value(metric.title, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [metric.tint.opacity(0.40), metric.tint.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", point.date),
                y: .value(metric.title, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(metric.tint)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

        case .line:
            LineMark(
                x: .value("Time", point.date),
                y: .value(metric.title, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(metric.tint)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

        case .bar:
            BarMark(
                x: .value("Time", point.date),
                y: .value(metric.title, point.value),
                width: .fixed(8)
            )
            .cornerRadius(3)
            .foregroundStyle(
                LinearGradient(
                    colors: [metric.tint, metric.tint.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    /// Y range: precipitation/humidity pin to 0–100; others pad the data so the
    /// trend isn't clipped against the top and bottom edges.
    private var yDomain: ClosedRange<Double> {
        if let fixed = metric.fixedDomain { return fixed }
        let values = points.map(\.value)
        let lo = (values.min() ?? 0) - 5
        let hi = (values.max() ?? 1) + 5
        return lo...max(hi, lo + 1)
    }
}

// MARK: - Flip transition

extension AnyTransition {
    /// A card flip that also scales and fades, so a tile appears to turn over
    /// and grow into the centered card (and reverses on dismiss).
    static var metricFlip: AnyTransition {
        .modifier(
            active: FlipScaleModifier(progress: 0),
            identity: FlipScaleModifier(progress: 1)
        )
    }
}

private struct FlipScaleModifier: ViewModifier {
    /// 0 = collapsed/edge-on, 1 = fully presented.
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.85 + 0.15 * progress)
            .rotation3DEffect(
                .degrees((1 - progress) * 90),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.4
            )
            .opacity(progress)
    }
}
