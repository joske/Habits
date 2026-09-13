//
//  CalendarView.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//

import SwiftUI

struct HabitMonthCalendar: View {
    @EnvironmentObject var database: DatabaseManager
    @AppStorage(SettingsKey.skipEnabled) private var skipEnabled = false
    @AppStorage(SettingsKey.shortToggleEnabled) private var shortToggle = false
    @State private var editingDay: EditingDay?

    let habit: Habit
    let monthStart: Date  // any date inside the month

    private var cal: Calendar { Calendar.current }

    private enum Cell: Hashable {
        case placeholder(Int)
        case day(Int)
    }

    private var firstOfMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: monthStart))!
    }
    private var monthAnchor: Date {  // noon avoids DST glitches
        cal.date(bySettingHour: 12, minute: 0, second: 0, of: firstOfMonth)!
    }
    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: monthAnchor)!.count
    }
    private var leading: Int {
        let weekdayOfFirst = cal.component(.weekday, from: monthAnchor)  // 1...7
        return (weekdayOfFirst - cal.firstWeekday + 7) % 7
    }
    private var cells: [Cell] {
        (0..<leading).map { .placeholder($0) }
            + Array(1...daysInMonth).map { .day($0) }
    }
    private var monthEnd: Date {
        cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthAnchor)!
    }
    private var dayMap: [Int: DayEntry] {
        database.dayMapForHabit(habit, from: firstOfMonth, to: monthEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle(firstOfMonth)).font(.headline)

            // Weekday header
            HStack {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdaySymbol(i))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(cells.indices, id: \.self) { i in
                    cellView(for: cells[i])
                }
            }
        }
        .padding(.vertical, 6)
        .sheet(item: $editingDay) { day in
            DayEditorView(day: day)
                .environmentObject(database)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date)
    }

    private func toggle(_ date: Date) {
        database.toggleEntry(
            habit, dayStart: database.dayStart(for: date),
            skipEnabled: skipEnabled)
    }

    private func edit(_ date: Date) {
        let day = database.dayStart(for: date)
        editingDay = EditingDay(
            habit: habit, dayStart: day,
            entry: database.entry(for: habit, dayStart: day))
    }

    private func weekdaySymbol(_ idx: Int) -> String {
        let c = Calendar.current
        let i = (idx + c.firstWeekday - 1) % 7
        return String(c.shortWeekdaySymbols[i].prefix(2)).uppercased()
    }

    @ViewBuilder
    private func cellView(for cell: Cell) -> some View {
        switch cell {
        case .placeholder:
            Color.clear.frame(height: 28)

        case .day(let day):
            let date = cal.date(
                byAdding: .day, value: day - 1, to: monthAnchor)!
            let key = (Int(date.timeIntervalSince1970) / 86_400) * 86_400
            let entry = dayMap[key] ?? .empty
            let done = habit.type == 0 ? entry.isYes : (entry.value > 0)
            let skipped = habit.type == 0 && entry.isSkip

            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(done ? habit.tint : Color.gray)
                        .opacity(skipped ? 0.35 : 1)
                        .frame(height: 28)
                    Text("\(day)")
                        .font(.caption2)
                        .foregroundStyle(done ? .white : .primary)
                }

                if entry.hasNote {
                    Circle()
                        .fill(done ? Color.white : habit.tint)
                        .frame(width: 5, height: 5)
                        .padding(3)
                        .accessibilityLabel("Has a note")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if shortToggle { toggle(date) } else { edit(date) }
            }
            .onLongPressGesture {
                if shortToggle { edit(date) } else { toggle(date) }
            }
        }
    }

}
