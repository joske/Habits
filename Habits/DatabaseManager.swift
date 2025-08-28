//
//  DatabaseManager.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import Foundation
import SQLite3

enum DBImportError: LocalizedError {
    case openFailed
    case invalidDatabase(String)
    case copyFailed(String)
    case schemaMismatch(String)

    var errorDescription: String? {
        switch self {
        case .openFailed: return "Could not open the database file."
        case .invalidDatabase(let msg): return "Integrity check failed: \(msg)"
        case .copyFailed(let msg): return "File operation failed: \(msg)"
        case .schemaMismatch(let msg): return "Schema mismatch: \(msg)"
        }
    }
}

class DatabaseManager: ObservableObject {
    private var db: OpaquePointer?
    private let dbPath: String

    @Published var habits: [Habit] = []
    @Published var todayRepetitions: [Int: Repetition] = [:]  // habit_id -> repetition
    // Map: habitId -> (dayOffset -> value)
    // dayOffset: 0 = today, 1 = yesterday, ...
    @Published var recentCompletions: [Int: [Int: Int]] = [:]

    init() {
        let fileURL = try! FileManager.default
            .url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
            .appendingPathComponent("habits.db")

        dbPath = fileURL.path
        openDatabase()
        createTables()
        loadHabits()
        loadTodayRepetitions()
    }

    deinit {
        closeDatabase()
    }

    // MARK: - Open/Close

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Unable to open database at \(dbPath)")
        }
    }

    private func closeDatabase() {
        if let handle = db {
            sqlite3_close(handle)
            db = nil
        }
    }

    private func reopenDatabase() {
        closeDatabase()
        openDatabase()
    }

    // MARK: - Schema bootstrap (for fresh installs)

    private func createTables() {
        let createHabitsTable = """
            CREATE TABLE IF NOT EXISTS Habits (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                archived INTEGER,
                color INTEGER,
                description TEXT,
                freq_den INTEGER,
                freq_num INTEGER,
                highlight INTEGER,
                name TEXT,
                position INTEGER,
                reminder_days INTEGER,
                reminder_hour INTEGER,
                reminder_min INTEGER,
                type integer not null default 0,
                target_type integer not null default 0,
                target_value real not null default 0,
                unit text not null default "",
                question text,
                uuid text
            );
            """

        let createRepetitionsTable = """
            CREATE TABLE IF NOT EXISTS Repetitions (
                id integer primary key autoincrement,
                habit integer not null references habits(id),
                timestamp integer not null,
                value integer not null,
                notes text
            );
            """

        let createEventsTable = """
            CREATE TABLE IF NOT EXISTS Events ( id integer primary key autoincrement, timestamp integer, message text, server_id integer );
            """

        let createMetadataTable = """
            CREATE TABLE IF NOT EXISTS android_metadata (locale TEXT);
            """

        let createIndex = """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_repetitions_habit_timestamp 
            on Repetitions(habit, timestamp);
            """

        if sqlite3_exec(db, createHabitsTable, nil, nil, nil) != SQLITE_OK {
            print("Unable to create Habits table")
        }
        if sqlite3_exec(db, createRepetitionsTable, nil, nil, nil) != SQLITE_OK
        {
            print("Unable to create Repetitions table")
        }
        if sqlite3_exec(db, createEventsTable, nil, nil, nil) != SQLITE_OK {
            print("Unable to create Events table")
        }
        if sqlite3_exec(db, createMetadataTable, nil, nil, nil) != SQLITE_OK {
            print("Unable to create Metadata table")
        }
        if sqlite3_exec(db, createIndex, nil, nil, nil) != SQLITE_OK {
            print("Unable to create index")
        }
    }

    // MARK: - Import external DB

    func importExternalDatabase(from pickedURL: URL) throws {
        // 1) Start security-scoped access (for iCloud/Files provider URLs)
        let needsSecurity = pickedURL.startAccessingSecurityScopedResource()
        defer { if needsSecurity { pickedURL.stopAccessingSecurityScopedResource() } }
        if !needsSecurity && !pickedURL.isFileURL {
            throw NSError(domain: "DatabaseManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not access the selected file."])
        }

        // 2) Coordinate the read to avoid permission errors
        var coordError: NSError?
        var readURL = pickedURL
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: pickedURL, options: .withoutChanges, error: &coordError) { url in
            readURL = url
        }
        if let e = coordError { throw e }

        // 3) Load file data
        guard let data = try? Data(contentsOf: readURL, options: [.mappedIfSafe]) else {
            throw NSError(domain: "DatabaseManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The selected file could not be read."])
        }

        // 4) Quick signature check: must start with "SQLite format 3\0"
        if data.count < 16 || String(data: data.prefix(16), encoding: .ascii) != "SQLite format 3\0" {
            throw NSError(domain: "DatabaseManager", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "File is not a valid SQLite database."])
        }

        // 5) Destination paths inside sandbox
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dest = docs.appendingPathComponent("habits.db")
        let temp = docs.appendingPathComponent("habits-import-\(UUID().uuidString).db")

        try data.write(to: temp, options: .atomic)

        // 6) Close current db handle if open
        if db != nil {
            sqlite3_close(db)
            db = nil
        }

        // 7) Backup old db, then replace with imported one
        let backup = docs.appendingPathComponent("habits-backup-\(Int(Date().timeIntervalSince1970))).db")
        if fm.fileExists(atPath: dest.path) {
            try? fm.copyItem(at: dest, to: backup)
        }
        if fm.fileExists(atPath: dest.path) {
            try fm.replaceItemAt(dest, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: dest)
        }

        // 8) Reopen and reload
        openDatabase()
        createTables()
        loadHabits()
        loadTodayRepetitions()
        loadRecentCompletions(lastNDays: 5)
    }

    private var appDBURL: URL {
        URL(fileURLWithPath: dbPath)
    }

    /// Returns binary data of a consistent DB snapshot.
    func exportDatabaseData() throws -> Data {
        // 1) Create a temp file
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "habits-export-\(UUID().uuidString).db"
            )
        // 2) Copy DB into temp using the SQLite backup API
        try backupDatabase(to: tmpURL.path)
        // 3) Read bytes
        let data = try Data(contentsOf: tmpURL)
        // 4) Clean up temp file (optional)
        try? FileManager.default.removeItem(at: tmpURL)
        return data
    }

    /// Uses sqlite3_backup to copy the live database to `destPath`.
    private func backupDatabase(to destPath: String) throws {
        var destDB: OpaquePointer?
        guard sqlite3_open(destPath, &destDB) == SQLITE_OK else {
            throw NSError(
                domain: "DBExport",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not open destination DB"
                ]
            )
        }
        defer { sqlite3_close(destDB) }

        guard let backup = sqlite3_backup_init(destDB, "main", db, "main")
        else {
            let msg = String(cString: sqlite3_errmsg(destDB))
            throw NSError(
                domain: "DBExport",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "backup_init failed: \(msg)"
                ]
            )
        }
        // Copy all pages (-1)
        let stepRC = sqlite3_backup_step(backup, -1)
        _ = sqlite3_backup_finish(backup)

        guard stepRC == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(destDB))
            throw NSError(
                domain: "DBExport",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "backup_step failed: \(stepRC) \(msg)"
                ]
            )
        }
    }
    // MARK: - Queries

    func loadHabits() {
        habits.removeAll()

        let querySQL = """
            SELECT Id, archived, color, description, freq_den, freq_num, highlight, name,
                   position, reminder_days, reminder_hour, reminder_min, type, target_type,
                   target_value, unit, question, uuid
            FROM Habits
            WHERE archived = 0
            ORDER BY position
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let habit = habitFromRow(statement)
                habits.append(habit)
            }
        }
        sqlite3_finalize(statement)
    }

    private enum HabitCol: Int32 {
        case id = 0
        case archived, color, description, freqDen, freqNum, highlight, name,
            position, reminderDays, reminderHour, reminderMin, type, targetType,
            targetValue, unit, question, uuid
    }

    private func habitFromRow(_ stmt: OpaquePointer!) -> Habit {
        Habit(
            id: Int(sqlite3_column_int(stmt, HabitCol.id.rawValue)),
            archived: Int(sqlite3_column_int(stmt, HabitCol.archived.rawValue)),
            color: Int(sqlite3_column_int(stmt, HabitCol.color.rawValue)),
            description: getString(
                statement: stmt, index: HabitCol.description.rawValue),
            freqDen: Int(sqlite3_column_int(stmt, HabitCol.freqDen.rawValue)),
            freqNum: Int(sqlite3_column_int(stmt, HabitCol.freqNum.rawValue)),
            highlight: Int(
                sqlite3_column_int(stmt, HabitCol.highlight.rawValue)),
            name: getString(statement: stmt, index: HabitCol.name.rawValue)
                ?? "Unknown",
            position: Int(sqlite3_column_int(stmt, HabitCol.position.rawValue)),
            reminderDays: Int(
                sqlite3_column_int(stmt, HabitCol.reminderDays.rawValue)),
            reminderHour: getInt(
                statement: stmt, index: HabitCol.reminderHour.rawValue),
            reminderMin: getInt(
                statement: stmt, index: HabitCol.reminderMin.rawValue),
            type: Int(sqlite3_column_int(stmt, HabitCol.type.rawValue)),
            targetType: Int(
                sqlite3_column_int(stmt, HabitCol.targetType.rawValue)),
            targetValue: sqlite3_column_double(
                stmt, HabitCol.targetValue.rawValue),
            unit: getString(statement: stmt, index: HabitCol.unit.rawValue)
                ?? "",
            question: getString(
                statement: stmt, index: HabitCol.question.rawValue),
            uuid: getString(statement: stmt, index: HabitCol.uuid.rawValue)
                ?? ""
        )
    }

    func loadRecentCompletions(lastNDays: Int = 5) {
        recentCompletions.removeAll()

        let day = Int(Date().timeIntervalSince1970) / 86400 * 86400
        let cutoff = day - (lastNDays - 1) * 86400

        let sql = """
                SELECT habit, timestamp, value
                FROM Repetitions
                WHERE timestamp >= ?
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(cutoff * 1000))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let habit = Int(sqlite3_column_int(stmt, 0))
                let tsDay =
                    Int(sqlite3_column_int64(stmt, 1)) / 86400 * 86400 / 1000
                let value = Int(sqlite3_column_int(stmt, 2))

                let offset = (day - tsDay) / 86400  // 0..lastNDays-1
                guard offset >= 0 && offset < lastNDays else { continue }

                var map = recentCompletions[habit] ?? [:]
                // If the same day has multiple repetitions, sum them (or set 1 if binary)
                map[offset] = (map[offset] ?? 0) + value
                recentCompletions[habit] = map
            }
        }
        sqlite3_finalize(stmt)
    }

    func loadHabit(id rowId: Int64) -> Habit? {
        let sql = """
            SELECT Id, archived, color, description, freq_den, freq_num, highlight, name,
                   position, reminder_days, reminder_hour, reminder_min, type, target_type,
                   target_value, unit, question, uuid
            FROM Habits
            WHERE Id = ?
            LIMIT 1;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print(
                "loadHabit prepare failed:", String(cString: sqlite3_errmsg(db))
            )
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, rowId)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            // not found
            return nil
        }

        return habitFromRow(stmt)
    }

    func loadTodayRepetitions() {
        todayRepetitions.removeAll()

        let today = Int(Date().timeIntervalSince1970 / 86400) * 86400  // Start of day timestamp

        let querySQL = """
            SELECT id, habit, timestamp, value, notes
            FROM Repetitions
            WHERE timestamp >= ?
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, Int64(today))

            while sqlite3_step(statement) == SQLITE_ROW {
                let repetition = Repetition(
                    id: Int(sqlite3_column_int(statement, 0)),
                    habit: Int(sqlite3_column_int(statement, 1)),
                    timestamp: Int(sqlite3_column_int64(statement, 2)),
                    value: Int(sqlite3_column_int(statement, 3)),
                    notes: getString(statement: statement, index: 4)
                )
                todayRepetitions[repetition.habit] = repetition
            }
        }
        sqlite3_finalize(statement)
    }

    func toggleHabit(_ habit: Habit, dayOffset: Int = 0) {
        let now = Int(Date().timeIntervalSince1970)
        let todayStart = (now / 86400) * 86400
        let targetDay = (todayStart - (dayOffset * 86400)) * 1000

        // Already done?
        let query =
            "SELECT id FROM Repetitions WHERE habit = ? AND timestamp = ?"
        var stmt: OpaquePointer?
        var existingId: Int?

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(habit.id))
            sqlite3_bind_int64(stmt, 2, Int64(targetDay))
            if sqlite3_step(stmt) == SQLITE_ROW {
                existingId = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        if let repId = existingId {
            // remove repetition
            let deleteSQL = "DELETE FROM Repetitions WHERE id = ?"
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(repId))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        } else {
            // insert repetition
            addRepetition(habitId: habit.id, timestamp: targetDay, value: 1)
        }

        loadTodayRepetitions()
        loadRecentCompletions(lastNDays: 5)
    }

    // MARK: - Inserts/Deletes

    func addHabit(name: String,
                  question: String,
                  notes: String?,
                  reminderDays: Int?,
                  reminderHour: Int?,
                  reminderMin: Int?) {
        let nextPosition = nextHabitPosition()
        let sql = """
            INSERT INTO Habits
            (name, question, description, archived, reminder_days, reminder_hour, reminder_min, position)
            VALUES (?, ?, ?, 0, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (question as NSString).utf8String, -1, nil)
            if let notes = notes, !notes.isEmpty {
                sqlite3_bind_text(stmt, 3, (notes as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let d = reminderDays { sqlite3_bind_int(stmt, 4, Int32(d)) } else { sqlite3_bind_null(stmt, 4) }
            if let h = reminderHour { sqlite3_bind_int(stmt, 5, Int32(h)) } else { sqlite3_bind_null(stmt, 5) }
            if let m = reminderMin { sqlite3_bind_int(stmt, 6, Int32(m)) } else { sqlite3_bind_null(stmt, 6) }
            sqlite3_bind_int64(stmt, 7, sqlite3_int64(nextPosition))

            _ = sqlite3_step(stmt)
        } else {
            print("addHabit prepare failed:", String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(stmt)
        loadHabits()
        loadTodayRepetitions()
        loadRecentCompletions()
    }


    func deleteHabit(_ habit: Habit) {
        let begin = "BEGIN IMMEDIATE TRANSACTION;"
        let delReps = "DELETE FROM Repetitions WHERE habit = ?;"
        let delHabit = "DELETE FROM Habits WHERE Id = ?;"
        let commit = "COMMIT;"

        var stmt: OpaquePointer?

        sqlite3_exec(db, begin, nil, nil, nil)

        // Delete repetitions
        if sqlite3_prepare_v2(db, delReps, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(habit.id))
            if sqlite3_step(stmt) != SQLITE_DONE {
                print(
                    "delete reps failed:", String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_finalize(stmt)

        // Delete habit
        if sqlite3_prepare_v2(db, delHabit, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(habit.id))
            if sqlite3_step(stmt) != SQLITE_DONE {
                print(
                    "delete habit failed:", String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_finalize(stmt)

        sqlite3_exec(db, commit, nil, nil, nil)

        // Refresh UI caches
        loadHabits()
        loadTodayRepetitions()
    }

    private func nextHabitPosition() -> Int {
        var stmt: OpaquePointer?
        let sql = "SELECT COALESCE(MAX(position), -1) + 1 FROM Habits;"
        var pos = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                pos = Int(sqlite3_column_int64(stmt, 0))
            }
        } else {
            print(
                "nextHabitPosition prepare failed:",
                String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(stmt)
        return pos
    }

    private func addRepetition(
        habitId: Int, timestamp: Int, value: Int, notes: String? = nil
    ) {
        let insertSQL = """
            INSERT OR REPLACE INTO Repetitions (habit, timestamp, value, notes) 
            VALUES (?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        let SQLITE_TRANSIENT = unsafeBitCast(
            -1, to: sqlite3_destructor_type.self)

        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(habitId))
            sqlite3_bind_int64(statement, 2, Int64(timestamp))
            sqlite3_bind_int(statement, 3, Int32(value))
            if let notes = notes, !notes.isEmpty {
                sqlite3_bind_text(
                    statement, 4, (notes as NSString).utf8String, -1,
                    SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            let rc = sqlite3_step(statement)
            if rc != SQLITE_DONE {
                print(
                    "addRepetition failed (rc=\(rc)):",
                    String(cString: sqlite3_errmsg(db)))
            }
        } else {
            print(
                "addRepetition prepare failed:",
                String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement)
    }

    private func deleteRepetition(_ repetition: Repetition) {
        guard let id = repetition.id else { return }

        let deleteSQL = "DELETE FROM Repetitions WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))
            let rc = sqlite3_step(statement)
            if rc != SQLITE_DONE {
                print(
                    "deleteRepetition failed (rc=\(rc)):",
                    String(cString: sqlite3_errmsg(db)))
            }
        } else {
            print(
                "deleteRepetition prepare failed:",
                String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement)
    }

    func updateHabit(
        habitId: Int,
        name: String,
        question: String,
        notes: String?,
        reminderDays: Int?,
        reminderHour: Int?,
        reminderMin: Int?
    ) {
        let sql = """
            UPDATE Habits
            SET name = ?, question = ?, description = ?,
                reminder_days = ?, reminder_hour = ?, reminder_min = ?
            WHERE Id = ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            // 1 name
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            // 2 question
            sqlite3_bind_text(stmt, 2, (question as NSString).utf8String, -1, nil)
            // 3 description / notes
            if let notes = notes, !notes.isEmpty {
                sqlite3_bind_text(stmt, 3, (notes as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            // 4 reminder_days
            if let d = reminderDays {
                sqlite3_bind_int(stmt, 4, Int32(d))
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            // 5 reminder_hour
            if let h = reminderHour {
                sqlite3_bind_int(stmt, 5, Int32(h))
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            // 6 reminder_min
            if let m = reminderMin {
                sqlite3_bind_int(stmt, 6, Int32(m))
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            // 7 id
            sqlite3_bind_int(stmt, 7, Int32(habitId))

            _ = sqlite3_step(stmt)
        } else {
            print("updateHabit prepare failed:", String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Column helpers

    private func getString(statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func getInt(statement: OpaquePointer?, index: Int32) -> Int? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    // MARK: - Scores (Loop Habit Tracker style)

    func scoresForHabit(_ habit: Habit, days: Int) -> [Score] {
        let to = Timestamp(date: Date())
        let from = to.minus(days - 1)

        // Build daily entries array (oldest → newest)
        let entries = entriesForHabit(habit, from: from, to: to)

        // Compute scores using Loop’s algorithm
        let scoreList = ScoreList()
        scoreList.recompute(
            frequency: Frequency(
                numerator: habit.freqNum, denominator: habit.freqDen),
            isNumerical: habit.type != 0,  // adapt if you model habit.type differently
            numericalHabitType: habit.targetType == 1 ? .atMost : .atLeast,
            targetValue: habit.targetValue,
            computedEntries: entries,
            from: from
        )

        // Return chronological order for charts
        return scoreList.getByInterval(from: from, to: to)
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Build one entry per day between [from, to], based on Repetitions in DB
    private func entriesForHabit(_ habit: Habit, from: Timestamp, to: Timestamp)
        -> [Int]
    {
        var result: [Int] = []
        var current = from

        while !current.isNewerThan(to) {
            // Find repetition for this day
            let dayStart = current.day * 86_400
            let rep = repetitionForHabit(habit.id, dayStart: dayStart)

            if let rep = rep {
                if habit.type == 0 {
                    if rep.value > 0 {
                        // Boolean habit: 1 = done
                        result.append(Entry.yesManual)
                    } else {
                        result.append(0)
                    }
                } else {
                    // Numerical habit: use stored value
                    result.append(rep.value)
                }
            } else {
                // No repetition logged
                result.append(0)
            }
            current = current.plus(1)
        }

        return result
    }

    /// Helper: fetch repetition for a habit on a given day (start-of-day timestamp)
    private func repetitionForHabit(_ habitId: Int, dayStart: Int)
        -> Repetition?
    {
        let querySQL = """
            SELECT id, habit, timestamp, value, notes
            FROM Repetitions
            WHERE habit = ? AND timestamp = ?
            LIMIT 1
            """

        var statement: OpaquePointer?
        var repetition: Repetition?

        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(habitId))
            sqlite3_bind_int64(statement, 2, Int64(dayStart * 1000))
            if sqlite3_step(statement) == SQLITE_ROW {
                repetition = Repetition(
                    id: Int(sqlite3_column_int(statement, 0)),
                    habit: Int(sqlite3_column_int(statement, 1)),
                    timestamp: Int(sqlite3_column_int64(statement, 2)),
                    value: Int(sqlite3_column_int(statement, 3)),
                    notes: getString(statement: statement, index: 4)
                )
            }
        }
        sqlite3_finalize(statement)

        return repetition
    }

    // MARK: - Day bucketing
    private lazy var timestampsAreMillis: Bool = {
        var stmt: OpaquePointer?
        var isMillis = false
        if sqlite3_prepare_v2(
            db, "SELECT MAX(timestamp) FROM Repetitions;", -1, &stmt, nil)
            == SQLITE_OK
        {
            if sqlite3_step(stmt) == SQLITE_ROW,
                sqlite3_column_type(stmt, 0) != SQLITE_NULL
            {
                let maxTs = sqlite3_column_int64(stmt, 0)
                isMillis = maxTs > 2_000_000_000  // > ~2033s epoch; if ms it's ~1e12
            }
        }
        sqlite3_finalize(stmt)
        return isMillis
    }()

    @inline(__always)
    private func dayStartSeconds(from epoch: Int) -> Int {
        let secs = epoch > 2_000_000_000 ? epoch / 1000 : epoch
        return (secs / 86_400) * 86_400
    }

    // All done-days (boolean) or day->sum (numeric) between dates
    func dayMapForHabit(_ habit: Habit, from: Date, to: Date) -> [Int: Int] {
        var map: [Int: Int] = [:]

        let cal = Calendar.current
        let fromStart = cal.startOfDay(for: from)
        // make 'to' inclusive at end of day (23:59:59)
        let toEndExclusive = cal.date(
            byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
        let fromS = Int(fromStart.timeIntervalSince1970)
        let toSInclusive = Int(toEndExclusive.timeIntervalSince1970) - 1

        let scale = timestampsAreMillis ? 1000 : 1
        let sql = """
                SELECT timestamp, value
                FROM Repetitions
                WHERE habit = ? AND timestamp BETWEEN ? AND ?
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(habit.id))
            sqlite3_bind_int64(stmt, 2, Int64(fromS * scale))
            sqlite3_bind_int64(stmt, 3, Int64(toSInclusive * scale))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let tsRaw = Int(sqlite3_column_int64(stmt, 0))
                let vRaw = Int(sqlite3_column_int(stmt, 1))
                let day = dayStartSeconds(from: tsRaw)
                if habit.type == 0 {
                    if vRaw > 0 { map[day] = 1 }  // boolean: mark done
                } else {
                    map[day, default: 0] += vRaw  // numeric: sum
                }
            }
        } else {
            print(
                "dayMapForHabit prepare failed:",
                String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(stmt)
        return map
    }

    // Count of done days per month (boolean) or days meeting target (numeric)
    struct MonthBucket: Identifiable {
        let id = UUID()
        let monthStart: Date
        let count: Int
    }

    func monthBuckets(for habit: Habit, monthsBack: Int) -> [MonthBucket] {
        let cal = Calendar.current
        let thisMonthStart = cal.date(
            from: cal.dateComponents([.year, .month], from: Date()))!
        var buckets: [MonthBucket] = []

        for i in stride(from: monthsBack - 1, through: 0, by: -1) {
            guard
                let monthStart = cal.date(
                    byAdding: .month, value: -i, to: thisMonthStart),
                let interval = cal.dateInterval(of: .month, for: monthStart)
            else { continue }

            // Build map for this exact month (inclusive)
            let dayMap = dayMapForHabit(
                habit, from: interval.start,
                to: interval.end.addingTimeInterval(-1))

            // Count days that are “done” in the month
            let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)!
                .count
            var count = 0
            // use NOON anchor (DST-safe)
            let anchor = cal.date(
                bySettingHour: 12, minute: 0, second: 0, of: interval.start)!
            for d in 0..<daysInMonth {
                let date = cal.date(byAdding: .day, value: d, to: anchor)!
                let key = (Int(date.timeIntervalSince1970) / 86_400) * 86_400
                if habit.type == 0 {
                    if dayMap[key] == 1 { count += 1 }
                } else {
                    // or compare against targetValue if you want “met target”
                    if (dayMap[key] ?? 0) > 0 { count += 1 }
                }
            }

            buckets.append(MonthBucket(monthStart: monthStart, count: count))
        }

        return buckets
    }

    // Toggle a specific calendar day (used by the calendar grid)
    func toggleHabit(_ habit: Habit, on date: Date) {
        let dayStart = (Int(date.timeIntervalSince1970) / 86_400) * 86_400

        // check existing
        var stmt: OpaquePointer?
        var existingId: Int?
        if sqlite3_prepare_v2(
            db, "SELECT id FROM Repetitions WHERE habit = ? AND timestamp = ?",
            -1, &stmt, nil) == SQLITE_OK
        {
            sqlite3_bind_int(stmt, 1, Int32(habit.id))
            sqlite3_bind_int64(stmt, 2, Int64(dayStart * 1000))
            if sqlite3_step(stmt) == SQLITE_ROW {
                existingId = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        if let id = existingId {
            if sqlite3_prepare_v2(
                db, "DELETE FROM Repetitions WHERE id = ?", -1, &stmt, nil)
                == SQLITE_OK
            {
                sqlite3_bind_int(stmt, 1, Int32(id))
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        } else {
            let sql =
                "INSERT INTO Repetitions (habit, timestamp, value, notes) VALUES (?, ?, 1, NULL)"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(habit.id))
                sqlite3_bind_int64(stmt, 2, Int64(dayStart * 1000))
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        loadTodayRepetitions()
        loadRecentCompletions()
    }

}
