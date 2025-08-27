//
//  HabitRowView.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HabitRowView: View {
    let habit: Habit
    let completions: [Int: Int]
    let onToggleDay: (Int) -> Void   // offset tapped

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let question = habit.question, !question.isEmpty {
                    Text(question)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if habit.hasReminder {
                    HStack {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                        Text("\(habit.reminderHour!):\(String(format: "%02d", habit.reminderMin!))")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }

            Spacer(minLength: 8)

            HabitHistoryStrip(
                color: Color.green,
                completions: completions,
                onToggleDay: onToggleDay,
            )

        }
        .padding(.vertical, 8)
    }
}
