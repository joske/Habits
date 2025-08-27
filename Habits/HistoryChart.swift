//
//  HistoryChart.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//

import SwiftUI
import Charts

struct MonthlyHistoryChart: View {
    let buckets: [DatabaseManager.MonthBucket]
    let barColor: Color

    private var chartWidth: CGFloat { max(CGFloat(buckets.count) * 25, 200) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    Chart(buckets) { b in
                        BarMark(
                            x: .value("Month", b.monthStart, unit: .month),
                            y: .value("Completions", Double(b.count))
                        )
                        .foregroundStyle(barColor)
                        .annotation(position: .top) {
                            Text("\(b.count)").font(.caption2).foregroundStyle(barColor)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: buckets.map { $0.monthStart }) { v in
                            if let d = v.as(Date.self) {
                                let m = Calendar.current.component(.month, from: d)
                                let y = Calendar.current.component(.year, from: d) % 100
                                AxisValueLabel {
                                    VStack(spacing: 1) {
                                        Text("\(m)").font(.caption2)
                                        Text(m == 1 ? "'\(y)" : " ").font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: chartWidth, height: 220)
                    .padding(.horizontal, 8)

                    Color.clear.frame(width: 1, height: 1).id("END")
                }
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo("END", anchor: .trailing) }
            }
            .onChange(of: buckets.count) { _, _ in
                DispatchQueue.main.async { proxy.scrollTo("END", anchor: .trailing) }
            }
        }
    }
}
