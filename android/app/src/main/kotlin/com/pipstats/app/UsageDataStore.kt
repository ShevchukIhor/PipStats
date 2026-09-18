package com.pipstats.app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Shared SQLite store. Mirrors the schema used by the Dart layer (sqflite),
 * so foreground/background events accumulate in one place regardless of
 * whether they are collected in the background (this worker) or in the
 * foreground (Dart). Path = same as sqflite default: databases/device_stats.db.
 */
class UsageDataStore(context: Context) :
    SQLiteOpenHelper(context, "device_stats.db", null, 4) {

  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL(
      """
      CREATE TABLE app_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package TEXT NOT NULL,
        event_type INTEGER NOT NULL,
        ts INTEGER NOT NULL
      )
      """.trimIndent()
    )
    db.execSQL("CREATE UNIQUE INDEX idx_events_dedup ON app_events(package, event_type, ts)")
    db.execSQL("CREATE INDEX idx_events_pkg_ts ON app_events(package, ts)")
    db.execSQL("CREATE INDEX idx_events_ts ON app_events(ts)")
    db.execSQL(
      """
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
      """.trimIndent()
    )
    db.execSQL(
      """
      CREATE TABLE daily_stats (
        package TEXT NOT NULL,
        day INTEGER NOT NULL,
        fg_ms INTEGER NOT NULL,
        PRIMARY KEY (package, day)
      )
      """.trimIndent()
    )
    db.execSQL(
      """
      CREATE TABLE battery_samples (
        ts INTEGER PRIMARY KEY,
        counter_uah INTEGER NOT NULL,
        current_ua INTEGER NOT NULL,
        charging INTEGER NOT NULL
      )
      """.trimIndent()
    )
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    if (oldVersion < 2) {
      db.execSQL(
        "DELETE FROM app_events WHERE id NOT IN " +
            "(SELECT MIN(id) FROM app_events GROUP BY package, event_type, ts)"
      )
      db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_events_dedup ON app_events(package, event_type, ts)")
    }
    if (oldVersion < 3) {
      db.execSQL(
        """
        CREATE TABLE IF NOT EXISTS daily_stats (
          package TEXT NOT NULL,
          day INTEGER NOT NULL,
          fg_ms INTEGER NOT NULL,
          PRIMARY KEY (package, day)
        )
        """.trimIndent()
      )
    }
    if (oldVersion < 4) {
      db.execSQL(
        """
        CREATE TABLE IF NOT EXISTS battery_samples (
          ts INTEGER PRIMARY KEY,
          counter_uah INTEGER NOT NULL,
          current_ua INTEGER NOT NULL,
          charging INTEGER NOT NULL
        )
        """.trimIndent()
      )
    }
  }

  override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    onUpgrade(db, newVersion, oldVersion)
  }

  fun getLastSyncTs(): Long {
    val db = readableDatabase
    db.rawQuery("SELECT value FROM meta WHERE key = 'last_sync_ts'", null).use { c ->
      if (c.moveToFirst()) return c.getString(0).toLongOrNull() ?: 0L
    }
    return 0L
  }

  fun setLastSyncTs(ts: Long) {
    val db = writableDatabase
    db.execSQL(
      "INSERT OR REPLACE INTO meta (key, value) VALUES ('last_sync_ts', ?)",
      arrayOf(ts.toString())
    )
  }

  /** Insert foreground(1)/background(0) events, dedup by (ts, package, type). */
  fun insertEvents(events: List<Map<String, Any?>>) {
    if (events.isEmpty()) return
    val db = writableDatabase
    db.beginTransaction()
    try {
      for (e in events) {
        db.execSQL(
          "INSERT OR IGNORE INTO app_events (package, event_type, ts) VALUES (?, ?, ?)",
          arrayOf(e["package"], e["event_type"], e["ts"])
        )
      }
      db.setTransactionSuccessful()
    } finally {
      db.endTransaction()
    }
  }

  /** Upsert per-package-per-day foreground totals (daily snapshot). */
  fun upsertDailyStats(rows: List<Map<String, Any?>>) {
    if (rows.isEmpty()) return
    val db = writableDatabase
    db.beginTransaction()
    try {
      for (r in rows) {
        db.execSQL(
          "INSERT OR REPLACE INTO daily_stats (package, day, fg_ms) VALUES (?, ?, ?)",
          arrayOf(r["package"], r["day"], r["fg_ms"])
        )
      }
      db.setTransactionSuccessful()
    } finally {
      db.endTransaction()
    }
  }
}