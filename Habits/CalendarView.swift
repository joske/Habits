//
//  CalendarView.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//

import SwiftUI

struct HabitMonthCalendar: View {
    @EnvironmentObject var database: DatabaseManager
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
    private var dayMap: [Int: Int] {
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
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date)
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
            let done =
                habit.type == 0 ? (dayMap[key] == 1) : ((dayMap[key] ?? 0) > 0)

            Button {
                database.toggleHabit(habit, on: date)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(done ? Color.green : Color.gray)
                        .frame(height: 28)
                    Text("\(day)")
                        .font(.caption2)
                        .foregroundStyle(done ? .white : .primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

}
