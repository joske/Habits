//
//  WeekdayChips.swift
//  Habits
//
//  Created by Jos Dehaes on 28/08/2025.
//
import SwiftUI

struct WeekdayChips: View {
    @Binding var dayToggles: [Bool] // Sun..Sat
    private let labels = Calendar.current.shortWeekdaySymbols // [Sun, Mon, …] in current locale

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Toggle(isOn: Binding(
                    get: { dayToggles[i] },
                    set: { dayToggles[i] = $0 }
                )) {
                    Text(labels[i].prefix(2).uppercased())
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20) // compact width
                }
                .toggleStyle(.button)
                .labelsHidden()
                .buttonStyle(.borderedProminent) // small filled chips
            }
        }
    }
}
