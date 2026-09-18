package com.pipstats.app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Fired by AlarmManager to collect usage events in the background (even when
 * the Flutter app is closed). Reads UsageStatsManager.queryEvents() since the
 * last sync marker and persists events into the shared SQLite store.
 */
class UsageReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent?) {
    if (intent?.action != ACTION_SYNC) return
    val pendingResult = goAsync()
    val store = UsageDataStore(context.applicationContext)
    // queryEvents + DB writes are not safe on the main thread; run them on IO.
    CoroutineScope(Dispatchers.IO).launch {
      try {
        collectEvents(context.applicationContext, store)
      } catch (_: Exception) {
        // ignore — next tick will retry
      } finally {
        store.close()
        pendingResult.finish()
      }
    }
  }

  private fun collectEvents(context: Context, store: UsageDataStore) {
    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val last = store.getLastSyncTs()
    val since = if (last > OVERLAP_MS) last - OVERLAP_MS else 0L
    val now = System.currentTimeMillis()
    val events = usm.queryEvents(since, now)
    val e = UsageEvents.Event()
    val out = mutableListOf<Map<String, Any?>>()

    while (events.hasNextEvent()) {
      events.getNextEvent(e)
      val type = when (e.eventType) {
        UsageEvents.Event.MOVE_TO_FOREGROUND -> 1
        UsageEvents.Event.MOVE_TO_BACKGROUND -> 0
        else -> -1
      }
      if (type != -1 && !e.packageName.isNullOrEmpty()) {
        out.add(
          mapOf(
            "package" to e.packageName,
            "event_type" to type,
            "ts" to e.timeStamp,
          )
        )
      }
    }

    store.insertEvents(out)
    store.setLastSyncTs(now)
    DailySnapshot.collect(context, store)
  }

  companion object {
    const val ACTION_SYNC = "com.pipstats.app.ACTION_SYNC"
    private const val OVERLAP_MS = 5 * 60 * 1000L
  }
}