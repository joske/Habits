//
//  HabitHistoryStrip.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HabitHistoryStrip: View {
    let color: Color
    let completions: [Int: Int]   // dayOffset -> value
    let days: Int = 5
    let onToggleDay: (Int) -> Void   // offset tapped

    var body: some View {
        HStack(spacing: 8) {
            ForEach((0..<days), id: \.self) { offset in
                let val = completions[offset] ?? 0
                DayBox(done: val > 0, color: color)
                    .onTapGesture { onToggleDay(offset) }
            }
        }
    }

    struct DayBox: View {
        let done: Bool
        let color: Color

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(done ? color : .secondary.opacity(0.25), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(done ? color.opacity(0.15) : Color.clear)
                    )
                    .frame(width: 28, height: 24)

                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                } else {
                    Text("×")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
        }
    }
}
