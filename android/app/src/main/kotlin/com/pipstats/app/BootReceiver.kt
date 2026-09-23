package com.pipstats.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Brings monitoring back up after a reboot.
 *
 * Without this the foreground service stayed down until the user next opened
 * the app, so every restart left a silent gap in the usage and battery
 * history — the one thing this app exists to record.
 *
 * Only re-arms what was already running: the collector and its alarm. It does
 * not open any UI.
 */
class BootReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent?) {
    val action = intent?.action ?: return
    if (action != Intent.ACTION_BOOT_COMPLETED &&
        action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
        action != "android.intent.action.QUICKBOOT_POWERON"
    ) {
      return
    }

    try {
      ForegroundService.start(context.applicationContext)
    } catch (e: Exception) {
      // Starting a foreground service at boot can be refused on some OEM
      // builds; the alarm below still keeps collection going.
      Log.w(TAG, "could not start service at boot: ${e.message}")
    }

    try {
      UsageReceiver.schedule(context.applicationContext)
    } catch (e: Exception) {
      Log.w(TAG, "could not schedule sync at boot: ${e.message}")
    }
  }

  private companion object {
    const val TAG = "BootReceiver"
  }
}
