//
//  HabitRowView.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HabitRowView<Menu: View>: View {
    let habit: Habit
    let entries: [Int: DayEntry]
    let onToggleDay: (Int) -> Void   // offset toggled
    let onEditDay: (Int) -> Void     // offset opened in the editor
    /// Long-pressing a day box toggles it, so the habit's own menu hangs off
    /// the name and question instead of the whole row.
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.headline)
                    .foregroundColor(habit.tint)

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
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu { menu() }

            Spacer(minLength: 8)

            HabitHistoryStrip(
                color: habit.tint,
                entries: entries,
                onToggleDay: onToggleDay,
                onEditDay: onEditDay
            )

        }
        .padding(.vertical, 8)
        .opacity(habit.archived == 0 ? 1 : 0.45)
    }
}
