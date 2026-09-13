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
        ScrollView {
            Text("Score").font(.headline)
            let scores = databaseManager.scoresForHabit(habit, days: 365)
            HabitStrengthChart(scores: scores, color: habit.tint)

            if let fresh = databaseManager.habits.first(where: {
                $0.id == habit.id
            }) {
                HabitHistorySection(habit: fresh)
                    .environmentObject(databaseManager)
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
            EditHabitView(habit: habit) { draft in
                databaseManager.updateHabit(habitId: habit.id, draft: draft)
                databaseManager.loadHabits()
                NotificationManager.shared.scheduleNotifications(
                    for: databaseManager.habits)
            }
        }
    }
}
