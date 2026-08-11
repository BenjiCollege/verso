import Accessibility
import Charts
import SwiftUI

/// Swift Charts, inked from the theme.
///
/// One chart type serves every series, because every series is the same shape.
/// No colour, size or curve here is a literal — a chart on `foxed` paper is
/// drawn in `foxed` ink.
struct MetricChart: View {

    enum Mark: String, Sendable {
        /// Counts and totals — water drunk, sets done.
        case bar
        /// Trends — bodyweight, a working max over months.
        case line
    }

    let points: [MetricPoint]
    let mark: Mark
    let unit: String
    /// Drawn as a dashed rule across the plot when present.
    var target: Double?
    /// A trailing mean over the bars. Empty when there aren't enough points.
    var trend: [MetricPoint] = []

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    var body: some View {
        Chart {
            ForEach(points) { point in
                switch mark {
                case .bar:
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(theme.accent)
                    .cornerRadius(Layout.Radius.tight / 2)
                case .line:
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(theme.accent)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(theme.accent)
                    .symbolSize(Layout.Space.snug)
                }
            }

            ForEach(trend) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trend", point.value),
                    series: .value("Series", "trend")
                )
                .foregroundStyle(theme.inkSecondary)
                .lineStyle(StrokeStyle(lineWidth: Layout.hairline * 2, dash: [4, 3]))
                .interpolationMethod(.monotone)
            }

            if let target {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(theme.inkSecondary)
                    .lineStyle(StrokeStyle(lineWidth: Layout.hairline * 2, dash: [2, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target")
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkSecondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisValueLabel()
                    .foregroundStyle(theme.inkSecondary)
                AxisGridLine()
                    .foregroundStyle(theme.rule)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(theme.inkSecondary)
                AxisGridLine()
                    .foregroundStyle(theme.rule)
            }
        }
        .chartLegend(.hidden)
        .animation(motion.animation(.settle), value: points)
        .accessibilityLabel(Text("Chart"))
        .accessibilityChartDescriptor(self)
    }
}

/// Makes the chart readable with Audio Graphs rather than announcing itself as
/// an image with no content.
extension MetricChart: AXChartDescriptorRepresentable {
    /// `nonisolated` because the protocol requirement is, and `View` otherwise
    /// infers main-actor isolation for it. Safe: it reads only the `let`
    /// properties, all of which are `Sendable`.
    nonisolated func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.map(\.value)
        let dates = points.map(\.date)

        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Date"),
            range: 0...Double(max(points.count - 1, 1)),
            gridlinePositions: []
        ) { index in
            let position = Int(index.rounded())
            guard dates.indices.contains(position) else { return "" }
            return dates[position].formatted(date: .abbreviated, time: .omitted)
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: unit.isEmpty ? String(localized: "Value") : unit,
            range: (values.min() ?? 0)...(values.max() ?? 1),
            gridlinePositions: []
        ) { value in
            let formatted = value.formatted(.number.precision(.fractionLength(0...2)))
            return unit.isEmpty ? formatted : "\(formatted) \(unit)"
        }

        let series = AXDataSeriesDescriptor(
            name: "",
            isContinuous: mark == .line,
            dataPoints: points.enumerated().map { index, point in
                AXDataPoint(x: Double(index), y: point.value)
            }
        )

        return AXChartDescriptor(
            title: String(localized: "Metric over time"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

/// The one-line chart shown inside a metric block. Small enough to sit under a
/// number without turning the page into a dashboard.
struct MetricSparkline: View {
    let points: [MetricPoint]

    @Environment(\.theme) private var theme

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value)
            )
            .foregroundStyle(theme.accent)
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: Layout.Space.airy)
        // The number beside it is the accessible content; a decorative
        // sparkline announcing itself twice is noise.
        .accessibilityHidden(true)
    }
}
