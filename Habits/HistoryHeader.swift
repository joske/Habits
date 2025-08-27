//
//  HistoryHeader.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HistoryHeader: View {
    let days: Int = 5
    var body: some View {
        let cal = Calendar.current
        let today = Date()
        HStack(spacing: 8) {
            Spacer()
            ForEach((0..<days), id: \.self) { offset in
                let d = cal.date(byAdding: .day, value: -offset, to: today)!
                Text(cal.shortWeekdaySymbols[cal.component(.weekday, from: d)-1].uppercased().prefix(3))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
            }
        }
        .padding(.horizontal)
    }
}
