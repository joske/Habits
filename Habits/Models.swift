//
//  Models.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import Foundation

struct Habit: Identifiable, Codable {
    let id: Int
    let archived: Int
    let color: Int
    let description: String?
    let freqDen: Int
    let freqNum: Int
    let highlight: Int
    let name: String
    let position: Int
    let reminderDays: Int
    let reminderHour: Int?
    let reminderMin: Int?
    let type: Int
    let targetType: Int
    let targetValue: Double
    let unit: String
    let question: String?
    let uuid: String

    var hasReminder: Bool {
        reminderHour != nil && reminderMin != nil && reminderDays > 0
    }

    var reminderTime: Date? {
        guard let hour = reminderHour, let min = reminderMin else { return nil }
        let calendar = Calendar.current
        let components = DateComponents(hour: hour, minute: min)
        return calendar.date(from: components)
    }
}

/// The editable fields of a habit, shared by the add and edit forms.
struct HabitDraft {
    var name: String
    var question: String
    var notes: String
    var color: Int
    var reminderDays: Int?
    var reminderHour: Int?
    var reminderMin: Int?

    init(
        name: String = "",
        question: String = "",
        notes: String = "",
        color: Int = HabitPalette.defaultIndex,
        reminderDays: Int? = nil,
        reminderHour: Int? = nil,
        reminderMin: Int? = nil
    ) {
        self.name = name
        self.question = question
        self.notes = notes
        self.color = color
        self.reminderDays = reminderDays
        self.reminderHour = reminderHour
        self.reminderMin = reminderMin
    }

    init(habit: Habit) {
        self.init(
            name: habit.name,
            question: habit.question ?? "",
            notes: habit.description ?? "",
            color: habit.color,
            reminderDays: habit.hasReminder ? habit.reminderDays : nil,
            reminderHour: habit.hasReminder ? habit.reminderHour : nil,
            reminderMin: habit.hasReminder ? habit.reminderMin : nil
        )
    }
}

struct Repetition: Identifiable, Codable {
    let id: Int?
    let habit: Int
    let timestamp: Int
    let value: Int
    let notes: String?
}

struct Timestamp: Hashable, Comparable {
    let day: Int  // midnight UTC days since epoch

    init(seconds: Int) {
        self.day = seconds / 86_400
    }

    init(day: Int) {
        self.day = day
    }

    init(date: Date) {
        self.day = Int(date.timeIntervalSince1970) / 86_400
    }

    func plus(_ offset: Int) -> Timestamp {
        Timestamp(day: day + offset)
    }

    func minus(_ offset: Int) -> Timestamp {
        Timestamp(day: day - offset)
    }

    func isNewerThan(_ other: Timestamp) -> Bool { self.day > other.day }
    func isOlderThan(_ other: Timestamp) -> Bool { self.day < other.day }

    static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.day < rhs.day
    }
}

struct Frequency {
    var numerator: Int
    var denominator: Int

    func toDouble() -> Double {
        Double(numerator) / Double(denominator)
    }
}

enum NumericalHabitType {
    case atLeast
    case atMost
}

/// Values stored in `Repetitions.value`, matching Loop's Entry constants.
/// Loop's migration 16 backfilled every existing repetition to `yesManual`,
/// so these are the numbers a Loop backup actually contains.
enum Entry {
    /// No data for this day. Loop does not store a row for it.
    static let unknown = -1
    /// The habit was expected but not performed.
    static let no = 0
    /// Not performed, but not expected either, because of the habit's
    /// frequency. Loop derives these for display; they do not build strength.
    static let yesAuto = 1
    /// The user checked this day off.
    static let yesManual = 2
    /// The day does not apply. Neutral: it neither builds nor decays strength.
    static let skip = 3

    /// True for values that count as done in the UI, skips excluded.
    static func isYes(_ value: Int) -> Bool {
        value == yesManual || value == yesAuto
    }
}

struct Score: Identifiable {
    var id: Int { timestamp.day }
    let timestamp: Timestamp
    let value: Double

    // This matches Score.Companion.compute() from Kotlin
    static func compute(_ freq: Double, _ prev: Double, _ percent: Double) -> Double {
        let multiplier = pow(0.5, sqrt(freq) / 13)
        var score = prev * multiplier
        score += percent * (1 - multiplier)
        return score
    }
}

final class ScoreList {
    private var map: [Timestamp: Score] = [:]

    subscript(timestamp: Timestamp) -> Score {
        map[timestamp] ?? Score(timestamp: timestamp, value: 0.0)
    }

    func getByInterval(from: Timestamp, to: Timestamp) -> [Score] {
        guard !from.isNewerThan(to) else { return [] }
        var current = to
        var result: [Score] = []
        while !current.isOlderThan(from) {
            result.append(self[current])
            current = current.minus(1)
        }
        return result
    }

    func recompute(
        frequency: Frequency,
        isNumerical: Bool,
        numericalHabitType: NumericalHabitType,
        targetValue: Double,
        computedEntries: [Int],  // one value per day in interval (oldest → newest)
        from: Timestamp
    ) {
        map.removeAll()

        var rollingSum = 0.0
        var numerator = frequency.numerator
        var denominator = frequency.denominator
        let freq = frequency.toDouble()
        let isAtMost = (numericalHabitType == .atMost)

        // For non-daily boolean habits, double numerator/denominator to smooth
        if !isNumerical && freq < 1.0 {
            numerator *= 2
            denominator *= 2
        }

        var previousValue = (isNumerical && isAtMost) ? 1.0 : 0.0

        // Walk day by day (oldest first)
        for i in 0..<computedEntries.count {
            let offset = computedEntries.count - i - 1
            let value = computedEntries[offset]

            if isNumerical {
                rollingSum += Double(max(0, value))
                if offset + denominator < computedEntries.count {
                    rollingSum -= Double(max(0, computedEntries[offset + denominator]))
                }

                let normalized = rollingSum / 1000.0
                if value != Entry.skip {
                    let percentageCompleted: Double
                    if !isAtMost {
                        percentageCompleted =
                            targetValue > 0
                            ? min(1.0, normalized / targetValue)
                            : 1.0
                    } else {
                        if targetValue > 0 {
                            percentageCompleted = (1 - ((normalized - targetValue) / targetValue))
                                .clamped(to: 0.0...1.0)
                        } else {
                            percentageCompleted = normalized > 0 ? 0.0 : 1.0
                        }
                    }
                    previousValue = Score.compute(freq, previousValue, percentageCompleted)
                }
            } else {
                if value == Entry.yesManual { rollingSum += 1 }
                if offset + denominator < computedEntries.count,
                    computedEntries[offset + denominator] == Entry.yesManual
                {
                    rollingSum -= 1
                }

                if value != Entry.skip {
                    let percentageCompleted = min(1.0, rollingSum / Double(numerator))
                    previousValue = Score.compute(freq, previousValue, percentageCompleted)
                }
            }

            let ts = from.plus(i)
            map[ts] = Score(timestamp: ts, value: previousValue)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Timestamp {
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    }
}
