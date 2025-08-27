//
//  ContentView.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var databaseManager = DatabaseManager()
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingAddHabit = false
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var habitPendingDelete: Habit?
    @State private var showDeleteConfirm = false
    @State private var showingExporter = false
    @State private var exportDoc: SQLiteDocument?
    @State private var exportError: String?

    var body: some View {
        NavigationView {
            List {
                ForEach(databaseManager.habits) { habit in
                    HabitRowView(
                        habit: habit,
                        isCompleted: databaseManager.todayRepetitions[habit.id] != nil,
                        onToggle: {
                            databaseManager.toggleHabit(habit)
                        }
                    )
                    .contentShape(Rectangle()) // ensure whole row is long-pressable
                    .contextMenu { // shows on long press
                        Button(role: .destructive) {
                            habitPendingDelete = habit
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Habit", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Habit")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .accessibilityLabel("Import Database")
                    }
                    Button {
                        do {
                            let data = try databaseManager.exportDatabaseData()
                            exportDoc = SQLiteDocument(data: data)
                            showingExporter = true
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Database")
                }
            }
            .confirmationDialog(
                "Delete this habit?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let h = habitPendingDelete {
                        databaseManager.deleteHabit(h)
                    }
                    habitPendingDelete = nil
                }
                Button("Cancel", role: .cancel) { habitPendingDelete = nil }
            } message: {
                Text("This will remove the habit and today’s repetitions.")
            }
            .sheet(isPresented: $showingAddHabit) {
                AddHabitView { name, question, notes, reminder in
                    databaseManager.addHabit(name: name, question: question, notes: notes.isEmpty ? nil : notes, reminder: reminder)
                    notificationManager.scheduleNotifications(for: databaseManager.habits)
                    databaseManager.loadHabits()
                }
            }
            .fileExporter(
                 isPresented: $showingExporter,
                 document: exportDoc,
                 contentType: UTType(filenameExtension: "db") ?? .data,
                 defaultFilename: defaultExportFilename()
             ) { result in
                 if case .failure(let err) = result { exportError = err.localizedDescription }
             }
             .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { _ in exportError = nil })) {
                 Button("OK", role: .cancel) {}
             } message: {
                 Text(exportError ?? "")
             }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "sqlite")!,
                    UTType(filenameExtension: "db")!,
                    UTType(filenameExtension: "sqlite3")!
                ],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    try databaseManager.importExternalDatabase(from: url)
                    databaseManager.loadHabits()
                    databaseManager.loadTodayRepetitions()
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        .onAppear {
            notificationManager.requestPermission()
            databaseManager.loadHabits()
            databaseManager.loadTodayRepetitions()
        }
        .refreshable {
            databaseManager.loadHabits()
            databaseManager.loadTodayRepetitions()
        }
    }
}

#Preview {
    ContentView()
}

private func defaultExportFilename() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd_HHmmss"
    return "habits_\(df.string(from: Date())).db"
}
