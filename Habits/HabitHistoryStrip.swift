//
//  HabitHistoryStrip.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

struct HabitHistoryStrip: View {
    let color: Color
    let entries: [Int: DayEntry]   // dayOffset -> entry
    let days: Int = 5
    let onToggleDay: (Int) -> Void   // offset toggled
    let onEditDay: (Int) -> Void     // offset opened in the editor

    @AppStorage(SettingsKey.shortToggleEnabled) private var shortToggle = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach((0..<days), id: \.self) { offset in
                let entry = entries[offset] ?? DayEntry.empty
                DayBox(entry: entry, color: color)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("day-\(offset)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Self.dayLabel(offset))
                    .accessibilityValue(Self.stateLabel(entry))
                    .onTapGesture {
                        if shortToggle { onToggleDay(offset) } else { onEditDay(offset) }
                    }
                    // A plain .onLongPressGesture loses to the List row's own
                    // recognizers, so this one has to outrank them
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            if shortToggle { onEditDay(offset) } else { onToggleDay(offset) }
                        }
                    )
            }
        }
    }

    /// The day this offset stands for, spelled out for VoiceOver.
    static func dayLabel(_ offset: Int) -> String {
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: -offset, to: Date())
        else { return "Day" }
        let df = DateFormatter()
        df.dateFormat = "EEEE"
        return offset == 0 ? "Today" : df.string(from: date)
    }

    static func stateLabel(_ entry: DayEntry) -> String {
        let state =
            entry.isYes ? "Done" : (entry.isSkip ? "Skipped" : "Not done")
        return entry.hasNote ? "\(state), has a note" : state
    }

    struct DayBox: View {
        let entry: DayEntry
        let color: Color

        var body: some View {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            entry.isYes || entry.isSkip
                                ? color : .secondary.opacity(0.25),
                            lineWidth: 1
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(entry.isYes ? color.opacity(0.15) : Color.clear)
                        )
                        .opacity(entry.isSkip ? 0.4 : 1)
                        .frame(width: 28, height: 24)

                    if entry.isYes {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                    } else if entry.isSkip {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color.opacity(0.5))
                    } else {
                        Text("×")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }

                if entry.hasNote {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("Has a note")
                }
            }
            .frame(width: 28, height: 24)
        }
    }
}
