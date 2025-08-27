//
//  HabitsApp.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI

@main
struct HabitsApp: App {
    init() {
        // Ensures delegate is set before any notifications can arrive
        DispatchQueue.main.async {
            NotificationManager.shared.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
