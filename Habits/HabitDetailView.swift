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

    let habitId: Int

    @State private var name = ""
    @State private var question = ""
    @State private var notes = ""
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()

    @State private var isLoaded = false

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $name)
                TextField("Question", text: $question)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            Section("Reminder") {
                Toggle("Daily reminder", isOn: $reminderEnabled.animation())
                if reminderEnabled {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                }
            }
        }
        .navigationTitle("Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard !isLoaded else { return }
        if let h = databaseManager.loadHabit(id: Int64(habitId)) {
            name = h.name
            question = h.question ?? ""
            notes = h.description ?? ""

            if let hr = h.reminderHour, let mn = h.reminderMin, h.reminderDays > 0 {
                reminderEnabled = true
                var comps = DateComponents()
                comps.hour = hr
                comps.minute = mn
                reminderTime = Calendar.current.date(from: comps) ?? reminderTime
            } else {
                reminderEnabled = false
            }
            isLoaded = true
        }
    }

    private func save() {
//        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
//        let hour = reminderEnabled ? comps.hour : nil
//        let minute = reminderEnabled ? comps.minute : nil
//        let daysMask = reminderEnabled ? 127 : 0 // all week if enabled
//
//        databaseManager.updateHabit(
//            id: habitId,
//            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
//            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
//            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
//            reminderDays: daysMask,
//            reminderHour: hour,
//            reminderMin: minute
//        )
//
//        // refresh list in parent and reschedule notifications if you want
//        databaseManager.loadHabits()
//        databaseManager.loadTodayRepetitions()
//        NotificationManager.shared.scheduleNotifications(for: databaseManager.habits)
//
        dismiss()
    }
}
