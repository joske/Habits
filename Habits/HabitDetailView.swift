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

    var body: some View {
        VStack {
            let scores = databaseManager.scoresForHabit(habit, days: 30)
            HabitStrengthChart(scores: scores)
            if let habit = databaseManager.habits.first(where: { $0.id == habit.id }) {
                ScrollView {
                    HabitHistorySection(habit: habit)
                        .environmentObject(databaseManager)
                }
            }
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
