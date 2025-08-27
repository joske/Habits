//
//  HabitStrengthChart.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import Charts
import SwiftUI

struct HabitStrengthChart: View {
    let scores: [Score]  // chronological scores (oldest → newest)

    var body: some View {
        Chart {
            ForEach(scores) { score in
                LineMark(
                    x: .value("Day", score.timestamp.date),
                    y: .value("Strength", score.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.blue)

                AreaMark(
                    x: .value("Day", score.timestamp.date),
                    y: .value("Strength", score.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .frame(height: 200)
        .padding()
    }
}
