//
//  HabitDetailView.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HabitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var databaseManager: DatabaseManager

    let habit: Habit
    @State private var showingEdit = false

    var body: some View {
        VStack {
            let scores = databaseManager.scoresForHabit(habit, days: 30)
            HabitStrengthChart(scores: scores)

            if let fresh = databaseManager.habits.first(where: { $0.id == habit.id }) {
                ScrollView {
                    HabitHistorySection(habit: fresh)
                        .environmentObject(databaseManager)
                }
            }
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditHabitView(habit: habit) { name, question, notes, reminderDays, hour, minute in
                databaseManager.updateHabit(
                    habitId: habit.id,
                    name: name,
                    question: question,
                    notes: notes.isEmpty ? nil : notes,
                    reminderDays: reminderDays,
                    reminderHour: hour,
                    reminderMin: minute
                )
                databaseManager.loadHabits()
                NotificationManager.shared.scheduleNotifications(for: databaseManager.habits)
            }
        }
    }
}
