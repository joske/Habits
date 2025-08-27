//
//  HabitRowView.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HabitRowView: View {
    let habit: Habit
    let isCompleted: Bool
    let onToggle: () -> Void

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

        }
        .padding(.vertical, 8)
    }
}
