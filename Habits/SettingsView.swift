//
//  SettingsView.swift
//  Habits
//
//  Created by Jos Dehaes on 13/09/2026.
//

import SwiftUI

/// Preference keys, mirroring Loop's own (pref_skip_enabled, pref_short_toggle).
enum SettingsKey {
    static let skipEnabled = "skipEnabled"
    static let shortToggleEnabled = "shortToggleEnabled"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.skipEnabled) private var skipEnabled = false
    @AppStorage(SettingsKey.shortToggleEnabled) private var shortToggleEnabled = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Enable skip days", isOn: $skipEnabled)
                } header: {
                    Text("Entries")
                } footer: {
                    Text(
                        "Adds a Skip button to the day editor. Skips keep your score unchanged and don't break your streak."
                    )
                }

                Section {
                    Toggle("Toggle with short press", isOn: $shortToggleEnabled)
                } footer: {
                    Text(
                        "Put checkmarks with a single tap instead of press-and-hold. Off, a tap opens the day editor, as Loop does by default."
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
