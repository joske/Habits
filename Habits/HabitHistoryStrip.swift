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
                DayBox(value: completions[offset] ?? Entry.no, color: color)
                    .onTapGesture { onToggleDay(offset) }
            }
        }
    }

    struct DayBox: View {
        let value: Int
        let color: Color

        private var done: Bool { Entry.isYes(value) }
        private var skipped: Bool { value == Entry.skip }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        done || skipped ? color : .secondary.opacity(0.25),
                        lineWidth: 1
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(done ? color.opacity(0.15) : Color.clear)
                    )
                    .opacity(skipped ? 0.4 : 1)
                    .frame(width: 28, height: 24)

                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                } else if skipped {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color.opacity(0.5))
                } else {
                    Text("×")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
        }
    }
}
