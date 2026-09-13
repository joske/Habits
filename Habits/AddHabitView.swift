//
//  AddHabitView.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//
import SwiftUI

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var question: String = ""
    @State private var notes: String = ""

    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var dayToggles: [Bool] = Array(repeating: true, count: 7) // Sun..Sat default ON

    let onSave: (HabitDraft) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Habit name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField("Question", text: $question)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled()

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section(header: Text("Reminder")) {
                    Toggle("Enable reminder", isOn: $reminderEnabled.animation())

                    if reminderEnabled {
                        DatePicker("Time",
                                   selection: $reminderTime,
                                   displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)

                        WeekdayChips(dayToggles: $dayToggles)
                            .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)

                        onSave(HabitDraft(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                            reminderDays: reminderEnabled ? bitmask(from: dayToggles) : nil,
                            reminderHour: reminderEnabled ? comps.hour : nil,
                            reminderMin: reminderEnabled ? comps.minute : nil
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (reminderEnabled && bitmask(from: dayToggles) == 0))
                }
            }
        }
    }

    private func bitmask(from toggles: [Bool]) -> Int {
        var m = 0
        for i in 0..<min(toggles.count, 7) {
            if toggles[i] { m |= (1 << i) } // bit 0 = Sunday ... bit 6 = Saturday
        }
        return m
    }
}
