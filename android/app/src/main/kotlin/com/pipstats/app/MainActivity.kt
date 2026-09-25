package com.pipstats.app

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.pm.ApplicationInfo
import android.net.ConnectivityManager
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.provider.OpenableColumns
import android.provider.Settings
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.hardware.display.DisplayManager
import android.view.Display
import android.app.ActivityManager
import android.telephony.TelephonyManager
import java.io.BufferedReader
import java.io.FileReader
import java.net.NetworkInterface
import java.util.Collections
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.roundToLong

class MainActivity : FlutterFragmentActivity() {

  private val CHANNEL = "device_stats/usage"

  private val TAG = "PipStats"

  /** True only for debuggable builds; keeps probe logging out of release. */
  private val isDebuggable: Boolean
    get() = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

  private companion object {
    const val OVERLAP_MS = 5 * 60 * 1000L
    const val REQ_POST_NOTIFICATIONS = 4711
  }

  /**
   * CSV export, held across the system save dialog.
   *
   * The picker is another activity, so the MethodChannel call cannot answer
   * inline — the content and the pending [MethodChannel.Result] wait here
   * until [finishCsvExport] runs.
   */
  private lateinit var createCsv: ActivityResultLauncher<String>
  private var pendingCsv: String? = null
  private var pendingCsvResult: MethodChannel.Result? = null

  override fun onDestroy() {
    WalletConnect.detach(this)
    super.onDestroy()
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    WalletConnect.attach(this)
    // Same constraint as WalletConnect's sender: registerForActivityResult is
    // only legal before the activity reaches STARTED, and configureFlutterEngine
    // runs inside onCreate.
    createCsv = registerForActivityResult(
      ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri -> finishCsvExport(uri) }
    // Only once the user has agreed. An install that has not been through
    // onboarding must not put a monitoring notification on screen, and an
    // existing Usage access grant counts as consent already given.
    if (MonitoringConsent.reconcile(this, hasUsageAccess())) {
      ForegroundService.start(this)
    }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "pollEvents" -> {
            val since = (call.argument<Number>("since") ?: 0).toLong()
            result.success(pollEvents(since))
          }
          "hasUsageAccess" -> result.success(hasUsageAccess())
          // Where "Allow restricted settings" lives, for installs Android has
          // flagged as sideloaded.
          "openOwnAppInfo" -> {
            openAppInfo(packageName)
            result.success(null)
          }
          "getUptimeMs" -> result.success(SystemClock.elapsedRealtime())
          "installedApps" -> result.success(installedApps())
          "getAppIconBase64" -> {
            val pkg = call.argument<String>("package")
            result.success(if (pkg != null) getAppIconBase64(pkg) else "")
          }
          "openAppInfo" -> {
            val pkg = call.argument<String>("package")
            if (pkg != null) openAppInfo(pkg)
            result.success(null)
          }
          "openUrl" -> {
            val url = call.argument<String>("url")
            result.success(if (url != null) openUrl(url) else false)
          }
          "openUsageSettings" -> {
            openUsageSettings()
            result.success(null)
          }
          "scheduleSync" -> {
            scheduleSync()
            result.success(null)
          }
          "syncNow" -> {
            syncNow()
            result.success(null)
          }
          "authorizeWallet" -> {
            WalletConnect.authorize(this, result)
          }
          "restoreWallet" -> {
            result.success(WalletConnect.saved(this))
          }
          "persistWallet" -> {
            val bytes = call.argument<List<Int>>("pubkey_bytes")
            if (bytes == null) {
              result.error("BAD_ARGS", "pubkey_bytes missing", null)
            } else {
              WalletConnect.persistWallet(this, bytes.map { it.toByte() }.toByteArray(), call.argument<String>("label"))
              result.success(null)
            }
          }
          "clearWallet" -> {
            WalletConnect.clearWallet(this)
            result.success(null)
          }
          "deauthorize" -> {
            WalletConnect.deauthorize(this, result)
          }
          "revokeDelegate" -> {
            val bytes = call.argument<List<Int>>("message_bytes")
            if (bytes == null) {
              result.error("BAD_ARGS", "message_bytes missing", null)
            } else {
              WalletConnect.signAndSend(this, bytes, result)
            }
          }
          "sendTip" -> {
            val bytes = call.argument<List<Int>>("message_bytes")
            if (bytes == null) {
              result.error("BAD_ARGS", "message_bytes missing", null)
            } else {
              WalletConnect.signAndSend(this, bytes, result)
            }
          }
          "networkUsage" -> {
            val since = call.argument<Long>("since") ?: 0L
            result.success(networkUsageSince(since))
          }
          "exportCsv" -> {
            val name = call.argument<String>("filename")
            val content = call.argument<String>("content")
            if (name == null || content == null) {
              result.error("BAD_ARGS", "filename and content required", null)
            } else {
              // A pending result that never got an answer would leave its Dart
              // Future hanging forever; close it out before taking a new one.
              pendingCsvResult?.success(mapOf("status" to "failed"))
              pendingCsv = content
              pendingCsvResult = result
              try {
                createCsv.launch(name)
              } catch (e: Exception) {
                // No document provider on the device.
                Log.w(TAG, "no save dialog: ${e.message}")
                pendingCsv = null
                pendingCsvResult = null
                result.success(mapOf("status" to "failed"))
              }
            }
          }
          "areNotificationsEnabled" -> result.success(areNotificationsEnabled())
          "requestNotificationPermission" -> {
            requestNotificationPermission()
            result.success(null)
          }
          "isIgnoringBatteryOptimizations" ->
            result.success(isIgnoringBatteryOptimizations())
          "requestIgnoreBatteryOptimizations" -> {
            requestIgnoreBatteryOptimizations()
            result.success(null)
          }
          "getMonitoringConsent" ->
            result.success(MonitoringConsent.reconcile(this, hasUsageAccess()))
          "setMonitoringConsent" -> {
            val granted = call.argument<Boolean>("granted") ?: false
            MonitoringConsent.set(this, granted)
            if (!granted) ForegroundService.stop(this)
            result.success(null)
          }
          "isServiceRunning" -> result.success(ForegroundService.isRunning)
          "startForegroundService" -> {
            ForegroundService.start(this)
            result.success(null)
          }
          "readBatteryInfo" -> result.success(readBatteryInfo())
          "getDeviceInfo" -> result.success(getDeviceInfo())
          "stopForegroundService" -> {
            ForegroundService.stop(this)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
  }

  /**
   * Whether our notifications are allowed to show.
   *
   * A foreground service runs regardless, but its notification is the only
   * thing that tells the user monitoring is on — and on Android 13+ it is
   * silently suppressed until POST_NOTIFICATIONS is granted. The app never
   * asked, so the ongoing notification was invisible on this device
   * (`appops POST_NOTIFICATION: ignore`).
   */
  /**
   * Per-package network bytes since [sinceMs], both mobile and Wi-Fi.
   *
   * NetworkStatsManager needs PACKAGE_USAGE_STATS, the same grant this app
   * already requires for usage events — so this adds a whole dimension of data
   * without asking for anything new.
   *
   * Buckets are per-UID, not per-package: a shared user id covers several
   * packages, so bytes are summed onto every package sharing that uid rather
   * than attributed to an arbitrary one.
   */
  private fun networkUsageSince(sinceMs: Long): List<Map<String, Any?>> {
    if (!hasUsageAccess()) return emptyList()
    val nsm = getSystemService(Context.NETWORK_STATS_SERVICE) as? NetworkStatsManager
      ?: return emptyList()
    val now = System.currentTimeMillis()
    val start = if (sinceMs > 0) sinceMs else now - 24 * 60 * 60 * 1000L

    val rxByUid = HashMap<Int, Long>()
    val txByUid = HashMap<Int, Long>()
    for (type in intArrayOf(ConnectivityManager.TYPE_MOBILE, ConnectivityManager.TYPE_WIFI)) {
      try {
        val stats = nsm.querySummary(type, null, start, now)
        val bucket = NetworkStats.Bucket()
        while (stats.hasNextBucket()) {
          stats.getNextBucket(bucket)
          rxByUid[bucket.uid] = (rxByUid[bucket.uid] ?: 0L) + bucket.rxBytes
          txByUid[bucket.uid] = (txByUid[bucket.uid] ?: 0L) + bucket.txBytes
        }
        stats.close()
      } catch (e: Exception) {
        // A type may be unavailable (no SIM, no permission for that subscriber).
        Log.w(TAG, "networkUsage type=$type: ${e.message}")
      }
    }

    val out = ArrayList<Map<String, Any?>>()
    val pm = packageManager
    for ((uid, rx) in rxByUid) {
      val packages = pm.getPackagesForUid(uid) ?: continue
      for (pkg in packages) {
        out.add(
          mapOf(
            "package" to pkg,
            "rx_bytes" to rx,
            "tx_bytes" to (txByUid[uid] ?: 0L),
          ),
        )
      }
    }
    return out
  }

  /**
   * Writes the pending CSV to wherever the user pointed the save dialog.
   *
   * The previous version wrote straight into the shared Downloads collection.
   * That was silent about where the file went, left it readable by every app
   * with media access, and outlived uninstalling this one — none of which the
   * privacy policy admitted to. It also could not work below Android 10, where
   * that route needs WRITE_EXTERNAL_STORAGE. Letting the user name the
   * destination fixes all three: the grant covers exactly the one file they
   * picked, and it needs no permission on any API level.
   *
   * A null [uri] means the dialog was dismissed. That is a choice, not a
   * failure, and the caller says so differently.
   */
  private fun finishCsvExport(uri: Uri?) {
    val content = pendingCsv
    val result = pendingCsvResult
    pendingCsv = null
    pendingCsvResult = null
    if (result == null) return
    if (uri == null) {
      result.success(mapOf("status" to "cancelled"))
      return
    }
    if (content == null) {
      // The process was killed while the picker was up and took the CSV with
      // it. The file the user picked stays empty; say so rather than lie.
      Log.w(TAG, "export lost its content across the picker")
      result.success(mapOf("status" to "failed"))
      return
    }
    try {
      val out = contentResolver.openOutputStream(uri)
        ?: throw IllegalStateException("no output stream for $uri")
      out.use { it.write(content.toByteArray(Charsets.UTF_8)) }
      result.success(mapOf("status" to "ok", "name" to documentName(uri)))
    } catch (e: Exception) {
      Log.w(TAG, "export failed: ${e.message}")
      result.success(mapOf("status" to "failed"))
    }
  }

  /**
   * The name the document provider actually gave the file.
   *
   * Providers de-duplicate on collision, so this can differ from the name that
   * was suggested — report what landed, not what was asked for.
   */
  private fun documentName(uri: Uri): String? = try {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
      ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
      ?: uri.lastPathSegment
  } catch (_: Exception) {
    uri.lastPathSegment
  }

  private fun areNotificationsEnabled(): Boolean =
    NotificationManagerCompat.from(this).areNotificationsEnabled()

  private fun requestNotificationPermission() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    if (areNotificationsEnabled()) return
    if (shouldShowRequestPermissionRationale(
        android.Manifest.permission.POST_NOTIFICATIONS,
      ) ||
      checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
        PackageManager.PERMISSION_GRANTED
    ) {
      requestPermissions(
        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
        REQ_POST_NOTIFICATIONS,
      )
    }
  }

  /**
   * Whether the system has exempted us from Doze/App Standby.
   *
   * MediaTek and other OEM builds kill background services aggressively; the
   * exemption is the only supported way to ask them not to. It is the user's
   * decision — we can only surface the system screen.
   *
   * Reading the state needs no permission, unlike asking for it.
   */
  private fun isIgnoringBatteryOptimizations(): Boolean {
    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
    return pm.isIgnoringBatteryOptimizations(packageName)
  }

  /**
   * Opens the system's battery optimization list so the user can exempt us.
   *
   * The targeted ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog would be
   * one tap shorter, but it requires REQUEST_IGNORE_BATTERY_OPTIMIZATIONS —
   * a restricted-use permission that got the app rejected from the dApp Store
   * (PER-001). The list below needs no permission at all and ends at the same
   * toggle, so the permission was the wrong price for saving that tap.
   */
  private fun requestIgnoreBatteryOptimizations() {
    if (isIgnoringBatteryOptimizations()) return
    try {
      startActivity(
        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        },
      )
    } catch (_: Exception) {
      // Some builds hide the list too; the app keeps working, just without
      // the exemption.
    }
  }

  private fun hasUsageAccess(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return false
    val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      appOps.unsafeCheckOpNoThrow(
        AppOpsManager.OPSTR_GET_USAGE_STATS,
        Process.myUid(),
        packageName,
      )
    } else {
      @Suppress("DEPRECATION")
      appOps.checkOpNoThrow(
        AppOpsManager.OPSTR_GET_USAGE_STATS,
        Process.myUid(),
        packageName,
      )
    }
    return mode == AppOpsManager.MODE_ALLOWED
  }

  private fun openAppInfo(packageName: String) {
    try {
      val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
      intent.data = Uri.parse("package:$packageName")
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      startActivity(intent)
    } catch (_: Exception) {
      // ignore
    }
  }

  /**
   * Hands an https URL to the browser.
   *
   * Deliberately not url_launcher: that plugin adds a `queries` entry for
   * https so it can resolve a handler first, which grows the very manifest
   * surface the dApp Store review asked us to shrink. Launching an intent
   * directly is not subject to package-visibility filtering, so no query is
   * needed — only the https check below, so a malformed link can never turn
   * into some other kind of intent.
   */
  private fun openUrl(url: String): Boolean {
    val uri = try {
      Uri.parse(url)
    } catch (_: Exception) {
      return false
    }
    if (!uri.scheme.equals("https", ignoreCase = true)) return false
    return try {
      startActivity(
        Intent(Intent.ACTION_VIEW, uri).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        },
      )
      true
    } catch (e: Exception) {
      // No browser installed, or the activity refused to start.
      Log.w(TAG, "openUrl($url): ${e.message}")
      false
    }
  }

  private fun openUsageSettings() {
    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
      startActivity(intent)
    } catch (_: Exception) {
      val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
      i.data = Uri.parse("package:$packageName")
      i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      startActivity(i)
    }
  }

  /** Collect usage events immediately (in-process, same as background worker). */
  private fun syncNow() {
    val store = UsageDataStore(applicationContext)
    try {
      val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
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
          out.add(mapOf("package" to e.packageName, "event_type" to type, "ts" to e.timeStamp))
        }
      }
      store.insertEvents(out)
      store.setLastSyncTs(now)
      DailySnapshot.collect(applicationContext, store)
    } catch (_: Exception) {
      // ignore
    } finally {
      store.close()
    }
  }

  /** Arm the repeating collector alarm (shared with BootReceiver). */
  private fun scheduleSync() = UsageReceiver.schedule(this)


  private fun readSysfs(path: String): Long? = try {
    val v = java.io.File(path).readText().trim()
    if (v.isEmpty()) null else v.toLong()
  } catch (_: Exception) {
    null
  }

  /**
   * Read battery/power fields. Primary source is Android's BatteryManager
   * (charge counter is exposed to apps on this device without BATTERY_STATS).
   * Falls back to reading the mtk-gauge sysfs, which works when SELinux allows
   * it but is denied as `untrusted_app` on enforcing devices. All values are
   * optional; missing fields come back as null so Dart can fall back.
   */
  private fun readBatteryInfo(): Map<String, Any?> {
    val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
    fun prop(id: Int): Long? = try {
      val v = bm?.getIntProperty(id) ?: Int.MIN_VALUE
      if (v <= 0) null else v.toLong()
    } catch (_: Exception) {
      null
    }

    val base = "/sys/class/power_supply/battery/"

    // Remaining charge counter (uAh): prefer BatteryManager, fall back to sysfs.
    val counter = prop(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
      ?: readSysfs(base + "charge_counter")

    // Get level/scale from sticky battery intent for capacity estimation.
    val intent = registerReceiver(null, android.content.IntentFilter(
      Intent.ACTION_BATTERY_CHANGED
    ))
    val scale = intent?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
    val level = intent?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1

    // Design capacity (uAh) comes from power_profile.xml. It is NOT
    // BATTERY_PROPERTY_CAPACITY — that property is a percentage per the
    // Android docs and returns 100 on this device — and not
    // charge_full_design either, which this MediaTek gauge reports in a
    // different scale (294000 for a 4500 mAh cell).
    val designCapacity = designCapacityMah()?.let { (it * 1000).roundToLong() }

    // Full capacity (uAh): prefer derived from counter * scale / level (more accurate
    // than sysfs charge_full on this device). Fall back to sysfs charge_full.
    val derivedFull: Long? = if (counter != null && counter > 0 && scale > 0 && level > 0) {
      (counter.toDouble() * scale / level).roundToLong()
    } else {
      null
    }
    val sysfsFull: Long? = readSysfs(base + "charge_full")
    val full: Long? = if (derivedFull != null) derivedFull else sysfsFull

    // Current (uA): BatteryManager CURRENT_NOW is also gated on most devices.
    val current = prop(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
      ?: readSysfs(base + "current_now")

    if (isDebuggable) {
      Log.d(TAG, "battery full=$full counter=$counter current=$current design=$designCapacity")
    }
    return mapOf(
      "chargeFullUah" to full,
      "chargeCounterUah" to counter,
      "currentNowUa" to current,
      "voltageNowUv" to readSysfs(base + "voltage_now"),
      "level" to if (level > 0) level.toLong() else null,
      "scale" to if (scale > 0) scale.toLong() else null,
      "designCapacityUah" to designCapacity,
    )
  }

  private fun installedApps(): List<Map<String, Any?>> {
    val pm = packageManager
    val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
    val out = mutableListOf<Map<String, Any?>>()
    for (app in apps) {
      val label = pm.getApplicationLabel(app).toString()
      out.add(
        mapOf(
          "package" to app.packageName,
          "label" to label,
        ),
      )
    }
    return out
  }

  private fun getAppIconBase64(packageName: String): String {
    return try {
      val pm = packageManager
      val info = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
      val icon: Drawable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        info.loadIcon(pm)
      } else {
        @Suppress("DEPRECATION")
        pm.getApplicationIcon(info)
      }
      val bitmap = iconToBitmap(icon, 96) ?: return ""
      val baos = ByteArrayOutputStream()
      bitmap.compress(Bitmap.CompressFormat.PNG, 80, baos)
      Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
    } catch (_: Exception) {
      ""
    }
  }

  private fun iconToBitmap(icon: Drawable, size: Int): Bitmap? {
    return try {
      // Bitmap icon: return its own bitmap directly (no manual rendering).
      if (icon is BitmapDrawable && icon.bitmap != null) {
        return Bitmap.createScaledBitmap(icon.bitmap, size, size, true)
      }

      // Everything else (incl. AdaptiveIconDrawable): let the drawable draw
      // itself onto a canvas. The system applies its own mask correctly.
      val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
      val canvas = Canvas(bitmap)
      icon.setBounds(0, 0, size, size)
      icon.draw(canvas)
      bitmap
    } catch (_: Exception) {
      null
    }
  }

  private fun pollEvents(since: Long): List<Map<String, Any?>> {
    val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val now = System.currentTimeMillis()
    val events = usm.queryEvents(since, now)
    val out = mutableListOf<Map<String, Any?>>()
    val e = UsageEvents.Event()

    while (events.hasNextEvent()) {
      events.getNextEvent(e)
      val type = when (e.eventType) {
        UsageEvents.Event.MOVE_TO_FOREGROUND -> 1
        UsageEvents.Event.MOVE_TO_BACKGROUND -> 0
        else -> -1
      }
      if (type != -1 && e.packageName != null && e.packageName.isNotEmpty()) {
        out.add(
          mapOf(
            "package" to e.packageName,
            "event_type" to type,
            "ts" to e.timeStamp,
          ),
        )
      }
    }
    val store = UsageDataStore(applicationContext)
    try {
      DailySnapshot.collect(applicationContext, store)
    } finally {
      store.close()
    }
    return out
  }

  private fun getDeviceInfo(): Map<String, Any?> {
    return mapOf(
      "device" to getDeviceInfoBlock(),
      "screen" to getScreenInfoBlock(),
      "battery" to getBatteryInfoBlock(),
      "storage" to getStorageInfoBlock(),
      "memory" to getMemoryInfoBlock(),
      "cpu" to getCpuInfoBlock(),
      "network" to getNetworkInfoBlock(),
    )
  }

  private fun getDeviceInfoBlock(): Map<String, Any?> {
    return mapOf(
      "model" to Build.MODEL,
      "brand" to Build.BRAND,
      "manufacturer" to Build.MANUFACTURER,
      "device" to Build.DEVICE,
      "product" to Build.PRODUCT,
      "hardware" to Build.HARDWARE,
      "board" to Build.BOARD,
      "cpuAbi" to Build.SUPPORTED_ABIS.joinToString(","),
      "androidVersion" to Build.VERSION.RELEASE,
      "sdkInt" to Build.VERSION.SDK_INT,
      "securityPatch" to Build.VERSION.SECURITY_PATCH,
      "fingerprint" to Build.FINGERPRINT,
      "serial" to try { Build.getSerial() } catch (_: Exception) { "Unknown" },
      "bootloader" to Build.BOOTLOADER,
      "radio" to Build.getRadioVersion(),
      "tags" to Build.TAGS,
      "type" to Build.TYPE,
      "user" to Build.USER,
      "host" to Build.HOST,
      "id" to Build.ID,
      "incremental" to Build.VERSION.INCREMENTAL,
      "codename" to Build.VERSION.CODENAME,
    )
  }

  private fun getScreenInfoBlock(): Map<String, Any?> {
    val dm = resources.displayMetrics
    val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    val display = displayManager.getDisplay(Display.DEFAULT_DISPLAY)
    val refreshRate = if (display != null) display.refreshRate.toDouble() else 0.0
    return mapOf(
      "widthPx" to dm.widthPixels.toLong(),
      "heightPx" to dm.heightPixels.toLong(),
      "density" to dm.density.toDouble(),
      "densityDpi" to dm.densityDpi.toLong(),
      "scaledDensity" to dm.scaledDensity.toDouble(),
      "xdpi" to dm.xdpi.toDouble(),
      "ydpi" to dm.ydpi.toDouble(),
      "refreshRateHz" to refreshRate,
      "orientation" to when (resources.configuration.orientation) {
        android.content.res.Configuration.ORIENTATION_PORTRAIT -> "Portrait"
        android.content.res.Configuration.ORIENTATION_LANDSCAPE -> "Landscape"
        else -> "Undefined"
      },
    )
  }

  /**
   * OEM-declared design capacity in mAh, from `power_profile.xml`.
   *
   * There is no public API for this. `BATTERY_PROPERTY_CAPACITY` is documented
   * as a *percentage*, not mAh, and `charge_full_design` on this MediaTek gauge
   * is reported in a different scale (294000 for a 4500 mAh cell) — both were
   * previously mistaken for the design capacity.
   *
   * `PowerProfile` is an internal class, so this is best-effort: null when the
   * platform refuses reflection.
   */
  private fun designCapacityMah(): Double? = try {
    val clazz = Class.forName("com.android.internal.os.PowerProfile")
    val instance = clazz.getConstructor(Context::class.java).newInstance(this)
    val value = clazz.getMethod("getBatteryCapacity").invoke(instance) as Double
    if (value > 0) value else null
  } catch (_: Throwable) {
    null
  }

  private fun getBatteryInfoBlock(): Map<String, Any?> {
    val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
    val intent = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    val health = intent?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1
    val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
    val technology = intent?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)
    val temperature = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
    val voltageMv = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
    val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
    val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
    val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1

    val healthStr = when (health) {
      BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
      BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheat"
      BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
      BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over Voltage"
      BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Unspecified Failure"
      BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
      else -> "Unknown"
    }
    val statusStr = when (status) {
      BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
      BatteryManager.BATTERY_STATUS_DISCHARGING -> "Discharging"
      BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not Charging"
      BatteryManager.BATTERY_STATUS_FULL -> "Full"
      else -> "Unknown"
    }
    val pluggedStr = when (plugged) {
      BatteryManager.BATTERY_PLUGGED_AC -> "AC"
      BatteryManager.BATTERY_PLUGGED_USB -> "USB"
      BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
      0 -> "Unplugged"
      else -> "Unknown"
    }

    // Remaining charge, µAh -> mAh.
    val counterUah = try {
      bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
    } catch (_: Exception) { 0 }
    val chargeCounterMah = if (counterUah > 0) counterUah / 1000.0 else null

    // Full capacity the gauge has *learned*. Extrapolated from the remaining
    // charge at the current level; equals charge_full when the cell is full.
    val fullCapacityMah = if (chargeCounterMah != null && level > 0 && scale > 0) {
      chargeCounterMah * scale / level
    } else {
      readSysfs("/sys/class/power_supply/battery/charge_full")?.let { it / 1000.0 }
    }

    val designMah = designCapacityMah()

    // No wear percentage is reported. It would be fullCapacity/design, but on
    // this device that is 2946/4500 = 65% for a cell with cycle_count = 1,
    // Android's min/last/max "learned" capacities all identical, and 0 mAh of
    // measured discharge — i.e. an uncalibrated gauge reading, not wear.
    // Telling wear from miscalibration needs cycle_count or the learned
    // history, and both are out of reach for an app: sysfs is blocked by
    // SELinux and batterystats needs the DUMP permission. Showing a confident
    // "65% health" from data that cannot support it is worse than showing
    // nothing.

    return mapOf(
      "levelPercent" to (if (level >= 0 && scale > 0) level * 100 / scale else null)?.toLong(),
      "status" to statusStr,
      "health" to healthStr,
      "plugged" to pluggedStr,
      "technology" to (technology ?: "Unknown"),
      "temperatureC" to (if (temperature > 0) temperature / 10.0 else null),
      "voltageV" to (if (voltageMv > 0) voltageMv / 1000.0 else null),
      "designCapacityMah" to designMah,
      // Labelled as the gauge's own figure, not as the battery's capacity:
      // it disagrees with the design capacity and cannot be trusted here.
      "gaugeReportedMah" to fullCapacityMah,
      "chargeCounterMah" to chargeCounterMah,
      "cycleCount" to readSysfs("/sys/class/power_supply/battery/cycle_count"),
    )
  }

  private fun getStorageInfoBlock(): Map<String, Any?> {
    // `filesDir` and `externalCacheDir` sit on the same physical volume on
    // modern Android (the latter is a FUSE view of the former), so reporting
    // both as "internal" and "external" double-counted one disk.
    val stat = StatFs(filesDir.absolutePath)
    val total = stat.blockCountLong * stat.blockSizeLong
    val free = stat.availableBlocksLong * stat.blockSizeLong
    return mapOf(
      "totalBytes" to total,
      "freeBytes" to free,
      "usedBytes" to (total - free),
    )
  }

  private fun getMemoryInfoBlock(): Map<String, Any?> {
    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val memInfo = ActivityManager.MemoryInfo()
    am.getMemoryInfo(memInfo)
    var totalMem = memInfo.totalMem
    var availMem = memInfo.availMem
    if (totalMem == 0L) {
      try {
        val reader = BufferedReader(FileReader("/proc/meminfo"))
        reader.useLines { lines ->
          lines.forEach { line ->
            if (line.startsWith("MemTotal:")) {
              totalMem = line.split("\\s+".toRegex()).getOrNull(1)?.toLongOrNull()?.let { it * 1024 } ?: 0L
            } else if (line.startsWith("MemAvailable:")) {
              availMem = line.split("\\s+".toRegex()).getOrNull(1)?.toLongOrNull()?.let { it * 1024 } ?: 0L
            }
          }
        }
      } catch (_: Exception) {}
    }
    val usedMem = totalMem - availMem
    return mapOf(
      "totalBytes" to totalMem.toLong(),
      "availableBytes" to availMem.toLong(),
      "usedBytes" to usedMem.toLong(),
      "lowMemory" to memInfo.lowMemory,
      "thresholdBytes" to memInfo.threshold.toLong(),
    )
  }

  private fun getCpuInfoBlock(): Map<String, Any?> {
    val cores = Runtime.getRuntime().availableProcessors()

    // Frequency must be scanned across every core. Reading only cpu0 reported
    // 2.0 GHz on this 4x A55 + 4x A78 SoC and hid the 2.5 GHz big cluster.
    var maxKhz = 0L
    var minKhz = Long.MAX_VALUE
    for (i in 0 until cores) {
      val dir = java.io.File("/sys/devices/system/cpu/cpu$i/cpufreq")
      val mx = readSysfs("${dir.path}/cpuinfo_max_freq")
      val mn = readSysfs("${dir.path}/cpuinfo_min_freq")
      if (mx != null && mx > maxKhz) maxKhz = mx
      if (mn != null && mn < minKhz) minKhz = mn
    }
    if (minKhz == Long.MAX_VALUE) minKhz = 0L

    // Group cores by their reported max frequency to describe the clusters,
    // e.g. "4x 2.50 GHz + 4x 2.00 GHz".
    val byFreq = sortedMapOf<Long, Int>(compareByDescending { it })
    for (i in 0 until cores) {
      val mx = readSysfs("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq") ?: continue
      byFreq[mx] = (byFreq[mx] ?: 0) + 1
    }
    val clusters = byFreq.entries.joinToString(" + ") { (khz, n) ->
      "${n}x %.2f GHz".format(khz / 1_000_000.0)
    }

    // ARM64 /proc/cpuinfo has no "model name" or "Hardware" line, so the SoC
    // name has to come from the build properties.
    val socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      Build.SOC_MODEL
    } else {
      Build.HARDWARE
    }
    val socVendor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      Build.SOC_MANUFACTURER
    } else {
      ""
    }

    return mapOf(
      "socModel" to socModel,
      "socManufacturer" to socVendor,
      "cores" to cores.toLong(),
      "clusters" to clusters,
      "maxFreqKhz" to maxKhz,
      "minFreqKhz" to minKhz,
      "abi" to Build.SUPPORTED_ABIS.joinToString(", "),
    )
  }

  private fun getNetworkInfoBlock(): Map<String, Any?> {
    // Flattened to "iface -> address" pairs: the previous nested list of maps
    // was rendered with toString() and came out as an unreadable dump.
    // Loopback, down and virtual (dummy*) interfaces are dropped, and MAC is
    // omitted because Android returns a fixed 02:00:00:00:00:00 to apps.
    val out = linkedMapOf<String, Any?>()
    try {
      Collections.list(NetworkInterface.getNetworkInterfaces()).forEach { ni ->
        if (!ni.isUp || ni.isLoopback || ni.name.startsWith("dummy")) return@forEach
        val v4 = ni.interfaceAddresses
          .mapNotNull { it.address.hostAddress }
          .firstOrNull { it.contains(".") }
        val v6 = ni.interfaceAddresses
          .mapNotNull { it.address.hostAddress }
          .firstOrNull { it.contains(":") && !it.startsWith("fe80") }
        if (v4 != null) out[ni.name] = v4
        if (v6 != null) out["${ni.name} (IPv6)"] = v6.substringBefore('%')
      }
    } catch (_: Exception) {
      // leave whatever was collected
    }

    val telephony = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
    if (telephony != null &&
        checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED) {
      val operator = telephony.networkOperatorName
      if (!operator.isNullOrBlank()) out["operator"] = operator
    }
    return out
  }
}
