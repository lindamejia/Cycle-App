import Charts
import SwiftUI

/// Thin grayscale chart for an insight's numbers. Highlighted points are drawn solid.
struct MiniChart: View {
    let series: ChartSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(series.yLabel)
            Chart {
                ForEach(Array(series.points.enumerated()), id: \.offset) { index, p in
                    if series.type == "line" {
                        LineMark(x: .value("x", index), y: .value("y", p.y))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        if p.highlight == true {
                            PointMark(x: .value("x", index), y: .value("y", p.y))
                                .foregroundStyle(Color.primary)
                                .symbolSize(18)
                        }
                    } else {
                        BarMark(x: .value("x", index), y: .value("y", p.y), width: .ratio(0.55))
                            .foregroundStyle(p.highlight == true ? Color.primary : Color.primary.opacity(0.22))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisIndices) { value in
                    AxisValueLabel {
                        if let i = value.as(Int.self), series.points.indices.contains(i) {
                            Text(series.points[i].x).font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: Theme.hairline)).foregroundStyle(Theme.rule)
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 120)
        }
    }

    private var axisIndices: [Int] {
        let n = series.points.count
        guard n > 1 else { return Array(0..<n) }
        let step = max(1, n / 4)
        var out = Array(stride(from: 0, to: n, by: step))
        if out.last != n - 1 { out.append(n - 1) }
        return out
    }
}
