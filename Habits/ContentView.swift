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
                HistoryHeader()
                ForEach(databaseManager.habits) { habit in
                    habitRow(for: habit)
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                toolbarItems
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
                Text("This will remove the habit and today's repetitions.")
            }
            .sheet(isPresented: $showingAddHabit) {
                addHabitSheet
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDoc,
                contentType: UTType(filenameExtension: "db") ?? .data,
                defaultFilename: defaultExportFilename()
            ) { result in
                if case .failure(let err) = result {
                    exportError = err.localizedDescription
                }
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { _ in exportError = nil }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "sqlite")!,
                    UTType(filenameExtension: "db")!,
                    UTType(filenameExtension: "sqlite3")!,
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        .onAppear {
            setupOnAppear()
        }
        .refreshable {
            refreshData()
        }
    }

    // MARK: - Helper Views
    @ViewBuilder
    private func habitRow(for habit: Habit) -> some View {
        let completions: [Int: Int] = databaseManager.recentCompletions[habit.id] ?? [:]

        NavigationLink(
            destination: HabitDetailView(habit: habit)
                .environmentObject(databaseManager)
        ) {
            HabitRowView(
                habit: habit,
                completions: completions,
                onToggleDay: { offset in
                    databaseManager.toggleHabit(habit, dayOffset: offset)
                }
            )
        }
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuItems(for: habit)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for habit: Habit) -> some View {
        Button(role: .destructive) {
            habitPendingDelete = habit
            showDeleteConfirm = true
        } label: {
            Label("Delete Habit", systemImage: "trash")
        }
    }

    private var toolbarItems: some ToolbarContent {
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
                handleExport()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Export Database")
        }
    }

    private var addHabitSheet: some View {
        AddHabitView { name, question, notes, reminder in
            databaseManager.addHabit(
                name: name,
                question: question,
                notes: notes.isEmpty ? nil : notes,
                reminder: reminder
            )
            notificationManager.scheduleNotifications(
                for: databaseManager.habits
            )
            databaseManager.loadHabits()
        }
    }

    // MARK: - Helper Functions
    private func handleExport() {
        do {
            let data = try databaseManager.exportDatabaseData()
            exportDoc = SQLiteDocument(data: data)
            showingExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try databaseManager.importExternalDatabase(from: url)
            databaseManager.loadHabits()
            databaseManager.loadRecentCompletions(lastNDays: 5)
            databaseManager.loadTodayRepetitions()
        } catch {
            print(Thread.callStackSymbols.joined(separator: "\n"))
            importError = error.localizedDescription
        }
    }

    private func setupOnAppear() {
        notificationManager.requestPermission()
        databaseManager.loadHabits()
        databaseManager.loadRecentCompletions(lastNDays: 5)
        databaseManager.loadTodayRepetitions()
    }

    private func refreshData() {
        databaseManager.loadHabits()
        databaseManager.loadRecentCompletions(lastNDays: 5)
        databaseManager.loadTodayRepetitions()
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
