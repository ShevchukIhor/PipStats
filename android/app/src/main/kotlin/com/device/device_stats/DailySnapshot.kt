package com.device.device_stats

import android.app.usage.UsageStatsManager
import android.content.Context
import java.util.Calendar

/**
 * Long-term retention via UsageStatsManager's daily buckets.
 *
 * queryEvents() only retains ~a few days; queryUsageStats(INTERVAL_DAILY)
 * exposes per-app per-day foreground totals further back. We snapshot those
 * totals into `daily_stats` so WEEK/MONTH/ALL can span multiple days even after
 * the event stream rolls out of the OS retention window.
 */
object DailySnapshot {

  /** Take a daily-foreground snapshot and upsert it into the store. */
  fun collect(context: Context, store: UsageDataStore) {
    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val end = System.currentTimeMillis()
    val begin = end - (365L * 24 * 60 * 60 * 1000L) // last 365 days
    val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, end)
    val rows = mutableListOf<Map<String, Any?>>()
    if (stats != null) {
      for (s in stats) {
        val pkg = s.packageName
        if (pkg.isNullOrEmpty()) continue
        val day = floorToLocalDay(s.firstTimeStamp)
        if (day <= 0L) continue
        val fg = s.totalTimeInForeground
        rows.add(mapOf("package" to pkg, "day" to day, "fg_ms" to fg))
      }
    }
    store.upsertDailyStats(rows)
  }

  /** Floor an epoch-ms timestamp to the start of its local calendar day. */
  private fun floorToLocalDay(tsMs: Long): Long {
    if (tsMs <= 0L) return 0L
    val cal = Calendar.getInstance().apply { timeInMillis = tsMs }
    cal.set(Calendar.HOUR_OF_DAY, 0)
    cal.set(Calendar.MINUTE, 0)
    cal.set(Calendar.SECOND, 0)
    cal.set(Calendar.MILLISECOND, 0)
    return cal.timeInMillis
  }
}