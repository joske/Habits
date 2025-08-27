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

struct Repetition: Identifiable, Codable {
    let id: Int?
    let habit: Int
    let timestamp: Int
    let value: Int
    let notes: String?
}
