//
//  DayEditorView.swift
//  Habits
//
//  Created by Jos Dehaes on 13/09/2026.
//

import SwiftUI

/// One day of one habit, as presented by the editor sheet.
struct EditingDay: Identifiable {
    let habit: Habit
    let dayStart: Int
    let entry: DayEntry

    var id: String { "\(habit.id)-\(dayStart)" }
}

/// Loop's checkmark dialog: the day's state and its note, edited together.
struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var database: DatabaseManager
    @AppStorage(SettingsKey.skipEnabled) private var skipEnabled = false

    let habit: Habit
    let dayStart: Int

    @State private var value: Int
    @State private var notes: String

    init(day: EditingDay) {
        habit = day.habit
        dayStart = day.dayStart
        // An imported yes-auto is shown, and saved, as a plain yes
        _value = State(
            initialValue: day.entry.isYes ? Entry.yesManual : day.entry.value)
        _notes = State(initialValue: day.entry.notes ?? "")
    }

    /// A skip stays selectable while it is the day's current state, even when
    /// the preference is off, so an imported skip cannot be silently lost.
    private var showsSkip: Bool { skipEnabled || value == Entry.skip }

    private var dateText: String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(dayStart)))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("State", selection: $value) {
                        Text("Yes").tag(Entry.yesManual)
                        if showsSkip {
                            Text("Skip").tag(Entry.skip)
                        }
                        Text("Clear").tag(Entry.no)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text(dateText)
                } footer: {
                    if value == Entry.skip {
                        Text(
                            "A skipped day keeps your score unchanged and doesn't break your streak."
                        )
                    }
                }

                Section("Note") {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        database.setEntry(
                            habit, dayStart: dayStart, value: value,
                            notes: notes)
                        dismiss()
                    }
                }
            }
        }
    }
}
