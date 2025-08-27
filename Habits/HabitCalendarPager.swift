//
//  HabitCalendarPager.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//


import SwiftUI

struct HabitCalendarPager: View {
    @EnvironmentObject var database: DatabaseManager
    let habit: Habit
    let monthsBack: Int = 13

    // compute months oldest → newest
    private var months: [Date] {
        let cal = Calendar.current
        let startOfThisMonth = cal.startOfDay(for: cal.date(from: cal.dateComponents([.year, .month], from: Date()))!)
        // 0..<(monthsBack) → [-i] → oldest first, newest last
        return (0..<monthsBack).reversed().compactMap { i in
            cal.date(byAdding: .month, value: -i, to: startOfThisMonth)
        }
    }

    @State private var selectedIndex: Int = 0

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selectedIndex) {
                ForEach(months.indices, id: \.self) { idx in
                    HabitMonthCalendar(habit: habit, monthStart: months[idx])
                        .environmentObject(database)
                        .frame(width: geo.size.width)  // full page
                        .padding(.horizontal, 16)
                        .tag(idx)                      // <-- tag with index
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onAppear {
                // jump to the last page (rightmost)
                selectedIndex = max(0, months.count - 1)
            }
            // if monthsBack changes or months recomputes, keep us on the last page
            .id(months.count) // forces TabView to rebuild when count changes
        }
        .frame(height: 280)
    }
}
