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
    @Published var todayRepetitions: [Int: Repetition] = [:] // habit_id -> repetition

    init() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
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

        if sqlite3_exec(db, createHabitsTable, nil, nil, nil) != SQLITE_OK { print("Unable to create Habits table") }
        if sqlite3_exec(db, createRepetitionsTable, nil, nil, nil) != SQLITE_OK { print("Unable to create Repetitions table") }
        if sqlite3_exec(db, createEventsTable, nil, nil, nil) != SQLITE_OK { print("Unable to create Events table") }
        if sqlite3_exec(db, createMetadataTable, nil, nil, nil) != SQLITE_OK { print("Unable to create Metadata table") }
        if sqlite3_exec(db, createIndex, nil, nil, nil) != SQLITE_OK { print("Unable to create index") }
    }

    // MARK: - Import external DB

    /// Validate -> backup -> replace -> reopen on the app's DB path.
    func importExternalDatabase(from url: URL) throws {
        // 1) Validate selected DB
        try validateDatabase(at: url)

        // 2) Backup current DB (+wal/+shm)
        try backupCurrentDatabase()

        // 3) Replace main DB file (and sibling WAL/SHM if present)
        try replaceAppDatabase(with: url)

        // 4) Reopen connection and reload
        reopenDatabase()
    }

    private var appDBURL: URL {
        URL(fileURLWithPath: dbPath)
    }

    private func validateDatabase(at url: URL) throws {
        var tempDB: OpaquePointer?
        guard sqlite3_open_v2(url.path, &tempDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, tempDB != nil else {
            throw DBImportError.openFailed
        }
        defer { sqlite3_close(tempDB) }

        // integrity_check
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(tempDB, "PRAGMA integrity_check;", -1, &stmt, nil) == SQLITE_OK else {
            throw DBImportError.invalidDatabase("prepare integrity_check failed")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw DBImportError.invalidDatabase("no result")
        }
        if let c = sqlite3_column_text(stmt, 0) {
            let res = String(cString: c)
            guard res.lowercased() == "ok" else {
                throw DBImportError.invalidDatabase(res)
            }
        }

        // Minimal schema check for Habits
        try assertHasTable(tempDB, "Habits", requiredColumns: [
            "Id","name","description","question",
            "freq_den","freq_num","type","target_type","target_value","unit"
        ])
    }

    private func assertHasTable(_ db: OpaquePointer?, _ table: String, requiredColumns: [String]) throws {
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBImportError.schemaMismatch("could not read table_info(\(table))")
        }
        defer { sqlite3_finalize(stmt) }

        var found = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cName = sqlite3_column_text(stmt, 1) {
                found.insert(String(cString: cName))
            }
        }
        let missing = Set(requiredColumns).subtracting(found)
        if !missing.isEmpty {
            throw DBImportError.schemaMismatch("missing columns: \(missing.sorted().joined(separator: ", "))")
        }
    }

    private func backupCurrentDatabase() throws {
        let fm = FileManager.default
        let src = appDBURL
        guard fm.fileExists(atPath: src.path) else { return }

        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = src.deletingLastPathComponent().appendingPathComponent("habits-backup-\(ts).db")
        try? fm.removeItem(at: backup)
        do { try fm.copyItem(at: src, to: backup) } catch { throw DBImportError.copyFailed(error.localizedDescription) }

        let wal = src.deletingPathExtension().appendingPathExtension("db-wal")
        let shm = src.deletingPathExtension().appendingPathExtension("db-shm")
        if fm.fileExists(atPath: wal.path) {
            let backupWAL = backup.deletingPathExtension().appendingPathExtension("db-wal")
            try? fm.copyItem(at: wal, to: backupWAL)
        }
        if fm.fileExists(atPath: shm.path) {
            let backupSHM = backup.deletingPathExtension().appendingPathExtension("db-shm")
            try? fm.copyItem(at: shm, to: backupSHM)
        }
    }

    private func replaceAppDatabase(with srcURL: URL) throws {
        let fm = FileManager.default
        let dst = appDBURL

        // Close before touching files
        closeDatabase()

        // Remove existing target files
        try? fm.removeItem(at: dst)
        let wal = dst.deletingPathExtension().appendingPathExtension("db-wal")
        let shm = dst.deletingPathExtension().appendingPathExtension("db-shm")
        try? fm.removeItem(at: wal)
        try? fm.removeItem(at: shm)

        // Copy main DB
        do { try fm.copyItem(at: srcURL, to: dst) }
        catch { throw DBImportError.copyFailed(error.localizedDescription) }

        // Copy sibling -wal / -shm if present (source folder)
        let base = srcURL.deletingPathExtension().lastPathComponent
        let dir = srcURL.deletingLastPathComponent()
        let srcWAL = dir.appendingPathComponent(base + "-wal")
        let srcSHM = dir.appendingPathComponent(base + "-shm")
        if fm.fileExists(atPath: srcWAL.path) {
            let dstWAL = dst.deletingPathExtension().appendingPathExtension("db-wal")
            _ = try? fm.copyItem(at: srcWAL, to: dstWAL)
        }
        if fm.fileExists(atPath: srcSHM.path) {
            let dstSHM = dst.deletingPathExtension().appendingPathExtension("db-shm")
            _ = try? fm.copyItem(at: srcSHM, to: dstSHM)
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
        case id = 0, archived, color, description, freqDen, freqNum, highlight, name,
             position, reminderDays, reminderHour, reminderMin, type, targetType,
             targetValue, unit, question, uuid
    }

    private func habitFromRow(_ stmt: OpaquePointer!) -> Habit {
        Habit(
            id: Int(sqlite3_column_int(stmt, HabitCol.id.rawValue)),
            archived: Int(sqlite3_column_int(stmt, HabitCol.archived.rawValue)),
            color: Int(sqlite3_column_int(stmt, HabitCol.color.rawValue)),
            description: getString(statement: stmt, index: HabitCol.description.rawValue),
            freqDen: Int(sqlite3_column_int(stmt, HabitCol.freqDen.rawValue)),
            freqNum: Int(sqlite3_column_int(stmt, HabitCol.freqNum.rawValue)),
            highlight: Int(sqlite3_column_int(stmt, HabitCol.highlight.rawValue)),
            name: getString(statement: stmt, index: HabitCol.name.rawValue) ?? "Unknown",
            position: Int(sqlite3_column_int(stmt, HabitCol.position.rawValue)),
            reminderDays: Int(sqlite3_column_int(stmt, HabitCol.reminderDays.rawValue)),
            reminderHour: getInt(statement: stmt, index: HabitCol.reminderHour.rawValue),
            reminderMin: getInt(statement: stmt, index: HabitCol.reminderMin.rawValue),
            type: Int(sqlite3_column_int(stmt, HabitCol.type.rawValue)),
            targetType: Int(sqlite3_column_int(stmt, HabitCol.targetType.rawValue)),
            targetValue: sqlite3_column_double(stmt, HabitCol.targetValue.rawValue),
            unit: getString(statement: stmt, index: HabitCol.unit.rawValue) ?? "",
            question: getString(statement: stmt, index: HabitCol.question.rawValue),
            uuid: getString(statement: stmt, index: HabitCol.uuid.rawValue) ?? ""
        )
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
            print("loadHabit prepare failed:", String(cString: sqlite3_errmsg(db)))
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

        let today = Int(Date().timeIntervalSince1970 / 86400) * 86400 // Start of day timestamp

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

    func toggleHabit(_ habit: Habit) {
        let now = Int(Date().timeIntervalSince1970)
        let dayTimestamp = (now / 86400) * 86400

        if let existingRep = todayRepetitions[habit.id] {
            deleteRepetition(existingRep)
        } else {
            addRepetition(habitId: habit.id, timestamp: dayTimestamp, value: 1)
        }

        loadTodayRepetitions()
    }

    // MARK: - Inserts/Deletes

    func addHabit(name: String, question: String, notes: String?, reminder: Date?) {
        // Compute next position (NULL sorts oddly; prefer explicit)
        let nextPosition = nextHabitPosition()

        let hasReminder = (reminder != nil)
        let (hour, minute): (Int32?, Int32?) = {
            guard let date = reminder else { return (nil, nil) }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (Int32(comps.hour ?? 0), Int32(comps.minute ?? 0))
        }()

        let sql = """
            INSERT INTO Habits
            (archived, color, description, freq_den, freq_num, highlight, name, position,
             reminder_days, reminder_hour, reminder_min, type, target_type, target_value, unit, question, uuid)
            VALUES
            (0, 0, ?, 1, 1, 0, ?, ?, ?, ?, ?, 0, 0, 0.0, "", ?, ?);
            """

        var stmt: OpaquePointer?
        // Ensure SQLite copies Swift strings
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("addHabit prepare failed:", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }

        // Bind 1: description (notes)
        if let notes = notes, !notes.isEmpty {
            sqlite3_bind_text(stmt, 1, (notes as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 1)
        }

        // Bind 2: name
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)

        // Bind 3: position
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(nextPosition))

        // 4 reminder_days (all days = 127) or 0 when disabled
        sqlite3_bind_int(stmt, 4, hasReminder ? 127 : 0)

        // 5 reminder_hour
        if let hour { sqlite3_bind_int(stmt, 5, hour) } else { sqlite3_bind_null(stmt, 5) }

        // 6 reminder_min
        if let minute { sqlite3_bind_int(stmt, 6, minute) } else { sqlite3_bind_null(stmt, 6) }

        // 7 question
        sqlite3_bind_text(stmt, 7, (question as NSString).utf8String, -1, SQLITE_TRANSIENT)

        // 8 uuid
        let uuid = UUID().uuidString
        sqlite3_bind_text(stmt, 8, (uuid as NSString).utf8String, -1, SQLITE_TRANSIENT)

        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            print("addHabit insert failed (rc=\(rc)):", String(cString: sqlite3_errmsg(db)))
            return
        }

        // Refresh UI-facing caches
        loadHabits()
        loadTodayRepetitions()
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
                    print("delete reps failed:", String(cString: sqlite3_errmsg(db)))
                }
            }
            sqlite3_finalize(stmt)

            // Delete habit
            if sqlite3_prepare_v2(db, delHabit, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(habit.id))
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("delete habit failed:", String(cString: sqlite3_errmsg(db)))
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
            print("nextHabitPosition prepare failed:", String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(stmt)
        return pos
    }

    private func addRepetition(habitId: Int, timestamp: Int, value: Int, notes: String? = nil) {
        let insertSQL = """
            INSERT OR REPLACE INTO Repetitions (habit, timestamp, value, notes) 
            VALUES (?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(habitId))
            sqlite3_bind_int64(statement, 2, Int64(timestamp))
            sqlite3_bind_int(statement, 3, Int32(value))
            if let notes = notes, !notes.isEmpty {
                sqlite3_bind_text(statement, 4, (notes as NSString).utf8String, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            let rc = sqlite3_step(statement)
            if rc != SQLITE_DONE {
                print("addRepetition failed (rc=\(rc)):", String(cString: sqlite3_errmsg(db)))
            }
        } else {
            print("addRepetition prepare failed:", String(cString: sqlite3_errmsg(db)))
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
                print("deleteRepetition failed (rc=\(rc)):", String(cString: sqlite3_errmsg(db)))
            }
        } else {
            print("deleteRepetition prepare failed:", String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Column helpers

    private func getString(statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func getInt(statement: OpaquePointer?, index: Int32) -> Int? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(statement, index))
    }
}
