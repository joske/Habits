//
//  NotificationManager.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func scheduleNotifications(for habits: [Habit]) {
        // Remove all existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        for habit in habits {
            print(habit)
            guard habit.hasReminder,
                  let hour = habit.reminderHour,
                  let minute = habit.reminderMin else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Habit Reminder"
            content.body = habit.question?.isEmpty == false ? habit.question! : "Time for \(habit.name)!"
            content.sound = UNNotificationSound.default

            // Schedule for each day of the week if reminder_days bit is set
            for day in 0..<7 {
                if (habit.reminderDays & (1 << day)) != 0 {
                    var dateComponents = DateComponents()
                    dateComponents.weekday = day + 1 // Sunday = 1
                    dateComponents.hour = hour
                    dateComponents.minute = minute

                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "\(habit.uuid)_\(day)",
                        content: content,
                        trigger: trigger
                    )

                    print("adding notification")
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }
}
