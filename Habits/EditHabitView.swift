//
//  EditHabitView.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//


import SwiftUI

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss

    let habit: Habit
    let onSave: (_ name: String, _ question: String, _ notes: String,
                 _ reminderDays: Int?, _ hour: Int?, _ minute: Int?) -> Void

    @State private var name: String
    @State private var question: String
    @State private var notes: String

    // Reminder UI state
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var dayToggles: [Bool] // Sun..Sat

    init(habit: Habit,
         onSave: @escaping (_ name: String, _ question: String, _ notes: String,
                            _ reminderDays: Int?, _ hour: Int?, _ minute: Int?) -> Void) {
        self.habit = habit
        self.onSave = onSave
        _name = State(initialValue: habit.name)
        _question = State(initialValue: habit.question ?? "")
        _notes = State(initialValue: habit.description ?? "")

        let hr = habit.reminderHour ?? 8
        let mn = habit.reminderMin ?? 0
        let comps = DateComponents(hour: hr, minute: mn)
        let date = Calendar.current.date(from: comps) ?? Date()

        _hasReminder = State(initialValue: habit.hasReminder)
        _reminderDate = State(initialValue: date)

        let mask = habit.reminderDays
        _dayToggles = State(initialValue: (0..<7).map { (mask & (1 << $0)) != 0 })
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Habit name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField("Question", text: $question)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Reminder") {
                    Toggle("Enable reminder", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("Time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                        WeekdayChips(dayToggles: $dayToggles)
                    }
                }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let mask = hasReminder ? bitmask(from: dayToggles) : nil
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
                        let hour = hasReminder ? comps.hour : nil
                        let minute = hasReminder ? comps.minute : nil
                        onSave(name, question, notes, mask, hour, minute)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func bitmask(from toggles: [Bool]) -> Int {
        var m = 0
        for i in 0..<min(toggles.count, 7) {
            if toggles[i] { m |= (1 << i) }
        }
        return m
    }
}
