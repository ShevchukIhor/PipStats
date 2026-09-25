package com.pipstats.app

import android.content.Context
import android.util.Log

/**
 * Whether the user has agreed to background monitoring.
 *
 * Kept in SharedPreferences rather than the app's SQLite store because
 * [BootReceiver] has to read it without a Flutter engine, and because the
 * service must not start before the answer is known.
 *
 * Until this existed the foreground service was started from
 * configureFlutterEngine on every launch, so a fresh install put an ongoing
 * "monitoring" notification on screen before the user had been told anything —
 * which is the substance of the dApp Store's PER-002 rejection.
 */
object MonitoringConsent {

  private const val PREFS = "monitoring"
  private const val KEY_GRANTED = "consent_granted"
  private const val TAG = "MonitoringConsent"

  /**
   * Device-protected storage, not the default.
   *
   * [BootReceiver] is directBootAware and answers LOCKED_BOOT_COMPLETED, so it
   * runs before the user unlocks. Credential-encrypted storage is unreadable
   * then and throws IllegalStateException, which crashed the receiver on every
   * boot and left monitoring down until the first unlock — exactly the gap
   * directBootAware exists to close. Whether the user agreed to measure their
   * own device is not a secret, so it belongs here.
   */
  private fun prefs(context: Context) =
    context.createDeviceProtectedStorageContext()
      .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /**
   * Fails closed: if the answer cannot be read, assume no consent rather than
   * start monitoring on a guess.
   */
  fun isGranted(context: Context): Boolean = try {
    prefs(context).getBoolean(KEY_GRANTED, false)
  } catch (e: Exception) {
    Log.w(TAG, "consent unreadable: ${e.message}")
    false
  }

  fun set(context: Context, granted: Boolean) {
    try {
      prefs(context).edit().putBoolean(KEY_GRANTED, granted).apply()
    } catch (e: Exception) {
      Log.w(TAG, "consent not saved: ${e.message}")
    }
  }

  /**
   * Treats an existing Usage access grant as consent already given.
   *
   * Without this, upgrading would drop every current user back to an
   * un-consented state and silently stop their monitoring. Someone who already
   * granted the permission this app is built around has plainly agreed to it.
   *
   * Returns the effective consent after any migration.
   */
  fun reconcile(context: Context, hasUsageAccess: Boolean): Boolean {
    if (isGranted(context)) return true
    if (!hasUsageAccess) return false
    set(context, true)
    return true
  }
}
