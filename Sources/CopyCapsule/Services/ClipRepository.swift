import Foundation
import SQLite3

/// Manages all persistence operations for clipboard items using SQLite3.
/// All methods are synchronous and should be called from a dedicated serial queue or MainActor.
final class ClipRepository {
    private var db: OpaquePointer?
    var dbPointer: OpaquePointer? { db }
    private let dbPath: String

    // MARK: - Init

    init(dbPath: String) throws {
        self.dbPath = dbPath
        try openDatabase()
        try setupSchema()          // 1. Create table if not exists (v2 schema)
        try migrateIfNeeded()      // 2. Migrate v1 → v2 if needed
        try setupIndexesAndFTS()   // 3. Create indexes and FTS (after migration ensures columns exist)
    }

    deinit {
        closeDatabase()
    }

    // MARK: - Open / Close

    private func openDatabase() throws {
        let rc = sqlite3_open_v2(
            dbPath,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard rc == SQLITE_OK, db != nil else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw RepositoryError.openFailed(msg)
        }
        // Enable WAL mode for better concurrent read performance
        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
    }

    private func closeDatabase() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    // MARK: - Schema (v3)

    /// Create the clip_items table (v3 schema). Safe to call on any database state.
    private func setupSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clip_items (
            id              TEXT PRIMARY KEY,
            type            TEXT NOT NULL CHECK(type IN ('text','image','rtf','file')),
            text_content    TEXT,
            image_data      BLOB,
            rtf_data        BLOB,
            file_path       TEXT,
            source_app_name TEXT,
            content_hash    TEXT NOT NULL,
            created_at      REAL NOT NULL,
            is_pinned       INTEGER NOT NULL DEFAULT 0,
            pinned_at       REAL,
            is_favorited    INTEGER NOT NULL DEFAULT 0,
            favorited_at    REAL,
            tags            TEXT NOT NULL DEFAULT '[]'
        );
        """
        let rc = sqlite3_exec(db, sql, nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw RepositoryError.schemaFailed(dbError())
        }
    }

    /// Create indexes and FTS virtual table. Must be called AFTER migration ensures
    /// all columns exist (is_favorited, etc.).
    private func setupIndexesAndFTS() throws {
        let sql = """
        CREATE INDEX IF NOT EXISTS idx_clip_created
            ON clip_items(created_at DESC);

        CREATE INDEX IF NOT EXISTS idx_clip_pinned
            ON clip_items(is_pinned);

        CREATE INDEX IF NOT EXISTS idx_clip_favorited
            ON clip_items(is_favorited);

        CREATE VIRTUAL TABLE IF NOT EXISTS clip_fts USING fts5(
            id UNINDEXED,
            text_content
        );
        """
        let rc = sqlite3_exec(db, sql, nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw RepositoryError.schemaFailed(dbError())
        }
    }

    // MARK: - Migration

    /// Migrate database from v1 to v2 schema.
    /// v1 schema lacked is_favorited, favorited_at, file_path columns
    /// and the CHECK constraint did not allow 'file' type.
    private func migrateIfNeeded() throws {
        let currentVersion = UserDefaults.standard.integer(forKey: dbSchemaVersionKey)

        // v2 → v3: add tags column
        if currentVersion == 2 {
            try migrateV2toV3()
            return
        }

        // Already v3+
        if currentVersion >= 3 { return }

        // Fresh DB with v2 columns → stamp v2 then migrate to v3
        if hasColumn("is_favorited") {
            UserDefaults.standard.set(2, forKey: dbSchemaVersionKey)
            try migrateV2toV3()
            return
        }

        // --- Full v1 → v2 migration ---
        print("[CopyCapsule] Migrating database from v1 to v2...")

        // 1. Create new table with v2 schema
        let createSQL = """
        CREATE TABLE clip_items_v2 (
            id              TEXT PRIMARY KEY,
            type            TEXT NOT NULL CHECK(type IN ('text','image','rtf','file')),
            text_content    TEXT,
            image_data      BLOB,
            rtf_data        BLOB,
            file_path       TEXT,
            source_app_name TEXT,
            content_hash    TEXT NOT NULL,
            created_at      REAL NOT NULL,
            is_pinned       INTEGER NOT NULL DEFAULT 0,
            pinned_at       REAL,
            is_favorited    INTEGER NOT NULL DEFAULT 0,
            favorited_at    REAL
        );
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw RepositoryError.schemaFailed("Migration create table failed: \(dbError())")
        }

        // 2. Copy existing data (new columns get defaults: NULL for file_path, 0 for is_favorited, NULL for favorited_at)
        let copySQL = """
        INSERT INTO clip_items_v2
            (id, type, text_content, image_data, rtf_data,
             source_app_name, content_hash, created_at, is_pinned, pinned_at)
        SELECT id, type, text_content, image_data, rtf_data,
               source_app_name, content_hash, created_at, is_pinned, pinned_at
        FROM clip_items
        """
        guard sqlite3_exec(db, copySQL, nil, nil, nil) == SQLITE_OK else {
            throw RepositoryError.schemaFailed("Migration copy failed: \(dbError())")
        }

        // 3. Drop old table
        guard sqlite3_exec(db, "DROP TABLE clip_items", nil, nil, nil) == SQLITE_OK else {
            throw RepositoryError.schemaFailed("Migration drop failed: \(dbError())")
        }

        // 4. Rename new table
        guard sqlite3_exec(db, "ALTER TABLE clip_items_v2 RENAME TO clip_items", nil, nil, nil) == SQLITE_OK else {
            throw RepositoryError.schemaFailed("Migration rename failed: \(dbError())")
        }

        // 5. Rebuild FTS (indexes are created later by setupIndexesAndFTS)
        _ = sqlite3_exec(db, "DROP TABLE IF EXISTS clip_fts", nil, nil, nil)
        _ = sqlite3_exec(db, """
            CREATE VIRTUAL TABLE IF NOT EXISTS clip_fts USING fts5(
                id UNINDEXED,
                text_content
            )
        """, nil, nil, nil)
        _ = sqlite3_exec(db, """
            INSERT INTO clip_fts (id, text_content)
            SELECT id, text_content FROM clip_items WHERE text_content IS NOT NULL
        """, nil, nil, nil)

        // 6. Stamp version
        UserDefaults.standard.set(2, forKey: dbSchemaVersionKey)
        print("[CopyCapsule] Database migration v1 → v2 complete.")

        // Continue to v3
        try migrateV2toV3()
    }

    /// Add tags column (v2 → v3).
    private func migrateV2toV3() throws {
        guard !hasColumn("tags") else {
            UserDefaults.standard.set(3, forKey: dbSchemaVersionKey)
            return
        }

        print("[CopyCapsule] Migrating database from v2 to v3 (adding tags)...")
        let sql = "ALTER TABLE clip_items ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw RepositoryError.schemaFailed("Migration v2→v3 failed: \(dbError())")
        }
        UserDefaults.standard.set(3, forKey: dbSchemaVersionKey)
        print("[CopyCapsule] Database migration v2 → v3 complete.")
    }

    /// Check if a column exists in clip_items table.
    private func hasColumn(_ columnName: String) -> Bool {
        let sql = "PRAGMA table_info(clip_items)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        guard let stmt else { return false }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = columnText(stmt, index: 1), name == columnName {
                return true
            }
        }
        return false
    }

    // MARK: - Insert

    func insert(_ item: ClipItem) throws {
        let sql = """
        INSERT INTO clip_items (id, type, text_content, image_data, rtf_data, file_path,
            source_app_name, content_hash, created_at, is_pinned, pinned_at, is_favorited, favorited_at, tags)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }

        bindUUID(stmt, index: 1, value: item.id)
        bindText(stmt, index: 2, value: item.type.rawValue)
        bindText(stmt, index: 3, value: item.textContent)
        bindBlob(stmt, index: 4, value: item.imageData)
        bindBlob(stmt, index: 5, value: item.rtfData)
        bindText(stmt, index: 6, value: item.filePath)
        bindText(stmt, index: 7, value: item.sourceAppName)
        bindText(stmt, index: 8, value: item.contentHash)
        bindDouble(stmt, index: 9, value: item.createdAt.timeIntervalSince1970)
        bindInt(stmt, index: 10, value: item.isPinned ? 1 : 0)
        if let pinnedAt = item.pinnedAt {
            bindDouble(stmt, index: 11, value: pinnedAt.timeIntervalSince1970)
        } else {
            bindNull(stmt, index: 11)
        }
        bindInt(stmt, index: 12, value: item.isFavorited ? 1 : 0)
        if let favoritedAt = item.favoritedAt {
            bindDouble(stmt, index: 13, value: favoritedAt.timeIntervalSince1970)
        } else {
            bindNull(stmt, index: 13)
        }
        bindText(stmt, index: 14, value: encodeTags(item.tags))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.insertFailed(dbError())
        }

        // Sync FTS index
        if let text = item.textContent {
            try insertFTS(id: item.id, text: text)
        }
    }

    // MARK: - Fetch

    func fetchRecent(limit: Int = 200) throws -> [ClipItem] {
        let sql = """
        SELECT id, type, text_content, image_data, rtf_data, file_path,
               source_app_name, content_hash, created_at, is_pinned, pinned_at,
               is_favorited, favorited_at, tags
        FROM clip_items
        WHERE is_pinned = 0 AND is_favorited = 0
        ORDER BY created_at DESC
        LIMIT ?
        """
        return try fetchWithSQL(sql) { [self] stmt in
            bindInt(stmt, index: 1, value: Int32(limit))
        }
    }

    func fetchPinned() throws -> [ClipItem] {
        let sql = """
        SELECT id, type, text_content, image_data, rtf_data, file_path,
               source_app_name, content_hash, created_at, is_pinned, pinned_at,
               is_favorited, favorited_at, tags
        FROM clip_items
        WHERE is_pinned = 1 AND is_favorited = 0
        ORDER BY pinned_at DESC
        """
        return try fetchWithSQL(sql)
    }

    func fetchFavorited() throws -> [ClipItem] {
        let sql = """
        SELECT id, type, text_content, image_data, rtf_data, file_path,
               source_app_name, content_hash, created_at, is_pinned, pinned_at,
               is_favorited, favorited_at, tags
        FROM clip_items
        WHERE is_favorited = 1
        ORDER BY favorited_at DESC
        """
        return try fetchWithSQL(sql)
    }

    // MARK: - Search (FTS5)

    func search(query: String, limit: Int = 100) throws -> [ClipItem] {
        // Substring search using LIKE — FTS5 only supports prefix matching.
        let likePattern = "%\(query)%"

        let sql = """
        SELECT id, type, text_content, image_data, rtf_data, file_path,
               source_app_name, content_hash, created_at, is_pinned, pinned_at,
               is_favorited, favorited_at, tags
        FROM clip_items
        WHERE text_content LIKE ? ESCAPE '\\'
        ORDER BY is_favorited DESC, is_pinned DESC, created_at DESC
        LIMIT ?
        """
        return try fetchWithSQL(sql) { [self] stmt in
            bindText(stmt, index: 1, value: likePattern)
            bindInt(stmt, index: 2, value: Int32(limit))
        }
    }

    // MARK: - Update

    func togglePin(id: UUID) throws {
        // Get current state
        let querySQL = "SELECT is_pinned FROM clip_items WHERE id = ?"
        var queryStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &queryStmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(queryStmt) }
        bindUUID(queryStmt, index: 1, value: id)
        guard sqlite3_step(queryStmt) == SQLITE_ROW else { return }
        let current = sqlite3_column_int(queryStmt, 0)
        // defer handles finalize — no explicit call (avoids double-free)

        let newPinned = (current == 0) ? 1 : 0
        let pinnedAt = (newPinned == 1) ? Date().timeIntervalSince1970 : nil

        let sql = "UPDATE clip_items SET is_pinned = ?, pinned_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindInt(stmt, index: 1, value: Int32(newPinned))
        if let pa = pinnedAt {
            bindDouble(stmt, index: 2, value: pa)
        } else {
            bindNull(stmt, index: 2)
        }
        bindUUID(stmt, index: 3, value: id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.updateFailed(dbError())
        }
    }

    func toggleFavorite(id: UUID) throws {
        // Get current state
        let querySQL = "SELECT is_favorited FROM clip_items WHERE id = ?"
        var queryStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &queryStmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(queryStmt) }
        bindUUID(queryStmt, index: 1, value: id)
        guard sqlite3_step(queryStmt) == SQLITE_ROW else { return }
        let current = sqlite3_column_int(queryStmt, 0)
        // defer handles finalize — no explicit call (avoids double-free)

        let newFavorited = (current == 0) ? 1 : 0
        let favoritedAt = (newFavorited == 1) ? Date().timeIntervalSince1970 : nil

        let sql = "UPDATE clip_items SET is_favorited = ?, favorited_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindInt(stmt, index: 1, value: Int32(newFavorited))
        if let fa = favoritedAt {
            bindDouble(stmt, index: 2, value: fa)
        } else {
            bindNull(stmt, index: 2)
        }
        bindUUID(stmt, index: 3, value: id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.updateFailed(dbError())
        }
    }

    // MARK: - Delete

    func delete(id: UUID) throws {
        let sql = "DELETE FROM clip_items WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, index: 1, value: id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.deleteFailed(dbError())
        }

        // Sync FTS
        try deleteFTS(id: id)
    }

    func deleteAll() throws {
        _ = sqlite3_exec(db, "DELETE FROM clip_items", nil, nil, nil)
        _ = sqlite3_exec(db, "DELETE FROM clip_fts", nil, nil, nil)
    }

    /// Delete only non-favorited, non-pinned items. Keeps favorites and pinned intact.
    func deleteRecent() throws {
        _ = sqlite3_exec(db, "DELETE FROM clip_items WHERE is_pinned = 0 AND is_favorited = 0", nil, nil, nil)
        try rebuildFTS()
    }

    // MARK: - Retention

    /// Auto-unpin items pinned longer than `days` days.
    /// Returns the count of unpinned items (they fall back to the Recent pool
    /// and will be cleaned up by purgeOlderThan on subsequent runs).
    func expirePinned(days: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970

        let sql = """
        UPDATE clip_items SET is_pinned = 0, pinned_at = NULL
        WHERE is_pinned = 1 AND pinned_at IS NOT NULL AND pinned_at < ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindDouble(stmt, index: 1, value: cutoff)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.updateFailed(dbError())
        }

        return Int(sqlite3_changes(db))
    }

    /// Deletes non-pinned, non-favorited items older than `days` days. Returns count of deleted items.
    func purgeOlderThan(days: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let countBefore = try totalCount()

        let sql = """
        DELETE FROM clip_items
        WHERE is_pinned = 0 AND is_favorited = 0 AND created_at < ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindDouble(stmt, index: 1, value: cutoff)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.deleteFailed(dbError())
        }

        // Also clean FTS entries for purged items (simple rebuild)
        try rebuildFTS()

        let countAfter = try totalCount()
        return countBefore - countAfter
    }

    // MARK: - Count

    func totalCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM clip_items"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - FTS Helpers

    private func insertFTS(id: UUID, text: String) throws {
        let sql = "INSERT INTO clip_fts (id, text_content) VALUES (?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, index: 1, value: id)
        bindText(stmt, index: 2, value: text)
        sqlite3_step(stmt)
    }

    private func deleteFTS(id: UUID) throws {
        let sql = "DELETE FROM clip_fts WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt, index: 1, value: id)
        sqlite3_step(stmt)
    }

    private func rebuildFTS() throws {
        // Delete all FTS entries and re-insert from clip_items
        _ = sqlite3_exec(db, "DELETE FROM clip_fts", nil, nil, nil)
        _ = sqlite3_exec(
            db,
            "INSERT INTO clip_fts (id, text_content) SELECT id, text_content FROM clip_items WHERE text_content IS NOT NULL",
            nil, nil, nil
        )
    }

    // MARK: - Generic fetch helper

    private func fetchWithSQL(
        _ sql: String,
        bind: ((OpaquePointer) -> Void)? = nil
    ) throws -> [ClipItem] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }

        bind?(stmt!)

        var items: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = rowToItem(stmt!) {
                items.append(item)
            }
        }
        return items
    }

    private func rowToItem(_ stmt: OpaquePointer) -> ClipItem? {
        guard
            let idStr = columnText(stmt, index: 0),
            let id = UUID(uuidString: idStr),
            let typeStr = columnText(stmt, index: 1),
            let type = ClipType(rawValue: typeStr)
        else { return nil }

        return ClipItem(
            id: id,
            type: type,
            textContent: columnText(stmt, index: 2),
            imageData: columnBlob(stmt, index: 3),
            rtfData: columnBlob(stmt, index: 4),
            filePath: columnText(stmt, index: 5),
            sourceAppName: columnText(stmt, index: 6),
            contentHash: columnText(stmt, index: 7) ?? "",
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
            isPinned: sqlite3_column_int(stmt, 9) != 0,
            pinnedAt: sqlite3_column_type(stmt, 10) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
                : nil,
            isFavorited: sqlite3_column_int(stmt, 11) != 0,
            favoritedAt: sqlite3_column_type(stmt, 12) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
                : nil,
            tags: decodeTags(columnText(stmt, index: 13))
        )
    }

    // MARK: - Binding helpers

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, index, (v as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindInt(_ stmt: OpaquePointer?, index: Int32, value: Int32) {
        sqlite3_bind_int(stmt, index, value)
    }

    private func bindDouble(_ stmt: OpaquePointer?, index: Int32, value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }

    private func bindBlob(_ stmt: OpaquePointer?, index: Int32, value: Data?) {
        if let v = value {
            _ = v.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, index, ptr.baseAddress, Int32(v.count), nil)
            }
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindNull(_ stmt: OpaquePointer?, index: Int32) {
        sqlite3_bind_null(stmt, index)
    }

    private func bindUUID(_ stmt: OpaquePointer?, index: Int32, value: UUID) {
        bindText(stmt, index: index, value: value.uuidString)
    }

    // MARK: - Column helpers

    private func columnText(_ stmt: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func columnBlob(_ stmt: OpaquePointer, index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: ptr, count: count)
    }

    // MARK: - Tags

    private func encodeTags(_ tags: [String]) -> String {
        guard !tags.isEmpty, let data = try? JSONEncoder().encode(tags),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private func decodeTags(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(tags.prefix(3))
    }

    /// Set tags for an item. Caps at 3. Returns the final tag list.
    func setTags(id: UUID, tags: [String]) throws -> [String] {
        let capped = Array(tags.prefix(3))
        let json = encodeTags(capped)
        let sql = "UPDATE clip_items SET tags = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, index: 1, value: json)
        bindUUID(stmt, index: 2, value: id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.updateFailed(dbError())
        }
        return capped
    }

    /// Fetch all distinct tags across all items (for autocomplete / tag cloud).
    func allTags() throws -> [String] {
        let sql = "SELECT tags FROM clip_items WHERE tags != '[]'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.prepareFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        guard let stmt else { throw RepositoryError.prepareFailed("nil stmt") }
        var set = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            for tag in decodeTags(columnText(stmt, index: 0)) {
                set.insert(tag)
            }
        }
        return Array(set).sorted()
    }

    /// Delete all items that have a specific tag. Returns the count of deleted items.
    @discardableResult
    func deleteByTag(_ tag: String) throws -> Int {
        let pattern = "%\"\(tag)\"%"
        // First count for return value
        var count: Int = 0
        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clip_items WHERE tags LIKE ?", -1, &countStmt, nil) == SQLITE_OK {
            bindText(countStmt, index: 1, value: pattern)
            if sqlite3_step(countStmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }
        // Delete from items and FTS
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clip_items WHERE tags LIKE ?", -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.deleteFailed(dbError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, index: 1, value: pattern)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            throw RepositoryError.deleteFailed(dbError())
        }
        // Sync FTS: delete orphaned entries
        try rebuildFTS()
        return count
    }

    /// Rename a tag across all items. Returns the count of updated items.
    @discardableResult
    func renameTag(from oldTag: String, to newTag: String) throws -> Int {
        let items = try fetchByTag(oldTag)
        var count = 0
        for item in items {
            var tags = item.tags
            guard let idx = tags.firstIndex(of: oldTag) else { continue }
            tags[idx] = newTag
            _ = try setTags(id: item.id, tags: tags)
            count += 1
        }
        return count
    }

    /// Fetch items matching a specific tag.
    func fetchByTag(_ tag: String, limit: Int = 200) throws -> [ClipItem] {
        let sql = """
        SELECT id, type, text_content, image_data, rtf_data, file_path,
               source_app_name, content_hash, created_at, is_pinned, pinned_at,
               is_favorited, favorited_at, tags
        FROM clip_items
        WHERE tags LIKE ?
        ORDER BY is_favorited DESC, is_pinned DESC, created_at ASC
        LIMIT ?
        """
        return try fetchWithSQL(sql) { [self] stmt in
            bindText(stmt, index: 1, value: "%\"\(tag)\"%")
            bindInt(stmt, index: 2, value: Int32(limit))
        }
    }

    /// Fetch items matching any of the given tags. Deduplicates by id.
    func fetchByTags(_ tags: [String], limit: Int = 200) throws -> [ClipItem] {
        guard !tags.isEmpty else { return [] }

        let placeholders = tags.map { _ in "tags LIKE ?" }.joined(separator: " OR ")
        let sql = """
        SELECT id, type, text_content, image_data, rtf_data, file_path,
               source_app_name, content_hash, created_at, is_pinned, pinned_at,
               is_favorited, favorited_at, tags
        FROM clip_items
        WHERE \(placeholders)
        ORDER BY is_favorited DESC, is_pinned DESC, created_at DESC
        LIMIT ?
        """
        return try fetchWithSQL(sql) { [self] stmt in
            for (i, tag) in tags.enumerated() {
                bindText(stmt, index: Int32(i + 1), value: "%\"\(tag)\"%")
            }
            bindInt(stmt, index: Int32(tags.count + 1), value: Int32(limit))
        }.reduce(into: []) { result, item in
            if !result.contains(where: { $0.id == item.id }) {
                result.append(item)
            }
        }
    }

    // MARK: - Error

    private func dbError() -> String {
        guard let db else { return "database closed" }
        return String(cString: sqlite3_errmsg(db))
    }
}

// MARK: - Keys

private let dbSchemaVersionKey = "db_schema_version"

// MARK: - Error Type

enum RepositoryError: LocalizedError {
    case openFailed(String)
    case schemaFailed(String)
    case prepareFailed(String)
    case insertFailed(String)
    case updateFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):    return "Failed to open database: \(m)"
        case .schemaFailed(let m):  return "Failed to create schema: \(m)"
        case .prepareFailed(let m): return "Failed to prepare statement: \(m)"
        case .insertFailed(let m):  return "Failed to insert item: \(m)"
        case .updateFailed(let m):  return "Failed to update item: \(m)"
        case .deleteFailed(let m):  return "Failed to delete item: \(m)"
        }
    }
}
