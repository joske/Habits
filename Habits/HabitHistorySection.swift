//
//  HabitHistorySection.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//

import SwiftUI

struct HabitHistorySection: View {
    @EnvironmentObject var database: DatabaseManager
    let habit: Habit
    let monthsBack: Int = 36

    var body: some View {
        Text("History").font(.headline)
        // Chart
        MonthlyHistoryChart(
            buckets: database.monthBuckets(for: habit, monthsBack: monthsBack),
            barColor: Color.blue
        )
        .padding(.horizontal)

        Text("Calendar").font(.headline)
        // Calendars
        HabitCalendarPager(habit: habit)
            .environmentObject(database)

    }
}
