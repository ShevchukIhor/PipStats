package com.device.device_stats

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Process
import android.os.StatFs
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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.roundToLong

class MainActivity : FlutterFragmentActivity() {

  private val CHANNEL = "device_stats/usage"

  private companion object {
    const val OVERLAP_MS = 5 * 60 * 1000L
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    WalletConnect.attach(this)
    // Start foreground service for background monitoring
    ForegroundService.start(this)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "pollEvents" -> {
            val since = (call.argument<Number>("since") ?: 0).toLong()
            result.success(pollEvents(since))
          }
          "hasUsageAccess" -> result.success(hasUsageAccess())
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
              WalletConnect.sendTip(this, bytes, result)
            }
          }
          "getDeviceInfo" -> result.success(getDeviceInfo())
          "stopForegroundService" -> {
            ForegroundService.stop(this)
            result.success(null)
          }
          else -> result.notImplemented()
        }
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

  /** Schedule a repeating AlarmManager broadcast every 15 minutes. */
  private fun scheduleSync() {
    val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val intent = Intent(this, UsageReceiver::class.java).apply {
      action = UsageReceiver.ACTION_SYNC
    }
    val pi = PendingIntent.getBroadcast(
      this,
      0,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val interval = 15 * 60 * 1000L
    am.setInexactRepeating(
      AlarmManager.RTC_WAKEUP,
      System.currentTimeMillis() + interval,
      interval,
      pi,
    )
  }

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

    // Design capacity (uAh): BATTERY_PROPERTY_CAPACITY returns design capacity in mAh
    // on supported devices per Android docs. However, some devices incorrectly return
    // the current UI level percentage (0-100) instead. We use a heuristic: value > 100
    // indicates mAh (design capacity), while <= 100 likely indicates a percentage.
    // Convert mAh to uAh for consistency.
    val designCapacity = try {
      val cap = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 0
      if (cap > 100) cap.toLong() * 1000 else null
    } catch (_: Exception) {
      null
    }

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

    Log.e("BATT_PROBE", "full=$full counter=$counter current=$current design=$designCapacity derived=$derivedFull sysfsFull=$sysfsFull")
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
      "orientation" to resources.configuration.orientation.toLong(),
    )
  }

  private fun getBatteryInfoBlock(): Map<String, Any?> {
    val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
    val intent = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    val health = intent?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1
    val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
    val technology = intent?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)
    val temperature = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
    val voltage = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
    val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
    val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
    val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
    val capacity = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    val chargeCounter = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
    val currentNow = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
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
      BatteryManager.BATTERY_STATUS_UNKNOWN -> "Unknown"
      else -> "Unknown"
    }
    val pluggedStr = when (plugged) {
      BatteryManager.BATTERY_PLUGGED_AC -> "AC"
      BatteryManager.BATTERY_PLUGGED_USB -> "USB"
      BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
      else -> "None"
    }

    // Derived full capacity: counter * scale / level (most accurate on this device)
    val derivedFull = if (chargeCounter != null && chargeCounter > 0 && scale > 0 && level > 0) {
      (chargeCounter.toDouble() * scale / level).roundToLong()
    } else null

    // Design capacity from BatteryManager (filtered >100 = mAh, else null)
    val designCap = try {
      val cap = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
      if (cap > 100) cap.toLong() * 1000 else null
    } catch (_: Exception) { null }

    // Sysfs fallback
    val sysfsFull = readSysfs("/sys/class/power_supply/battery/charge_full")

    return mapOf(
      "level" to level.toLong(),
      "scale" to scale.toLong(),
      "health" to healthStr,
      "status" to statusStr,
      "technology" to (technology ?: "Unknown"),
      "temperatureC" to (temperature.toDouble() / 10.0),
      "voltageV" to (voltage.toDouble() / 1000.0),
      "plugged" to pluggedStr,
      "capacityPercent" to capacity.toLong(),
      "chargeCounterUah" to chargeCounter?.toLong(),
      "currentNowUa" to currentNow?.toLong(),
      "fullCapacityUah" to (derivedFull ?: sysfsFull),
      "designCapacityUah" to designCap,
      "sysfsFullUah" to sysfsFull,
    )
  }

  private fun getStorageInfoBlock(): Map<String, Any?> {
    val internalPath = filesDir.absolutePath
    val internalStat = StatFs(internalPath)
    val internalTotal = internalStat.blockCountLong * internalStat.blockSizeLong
    val internalFree = internalStat.availableBlocksLong * internalStat.blockSizeLong
    val internalUsed = internalTotal - internalFree
    val externalPath = externalCacheDir?.absolutePath ?: ""
    var externalTotal = 0L
    var externalFree = 0L
    var externalUsed = 0L
    if (externalPath.isNotEmpty()) {
      val stat = StatFs(externalPath)
      externalTotal = stat.blockCountLong * stat.blockSizeLong
      externalFree = stat.availableBlocksLong * stat.blockSizeLong
      externalUsed = externalTotal - externalFree
    }
    return mapOf(
      "internalTotalBytes" to internalTotal.toLong(),
      "internalFreeBytes" to internalFree.toLong(),
      "internalUsedBytes" to internalUsed.toLong(),
      "externalTotalBytes" to externalTotal.toLong(),
      "externalFreeBytes" to externalFree.toLong(),
      "externalUsedBytes" to externalUsed.toLong(),
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
    var cpuInfo = ""
    var maxFreq = 0L
    var minFreq = 0L
    try {
      val reader = BufferedReader(FileReader("/proc/cpuinfo"))
      cpuInfo = reader.readText()
      reader.close()
      val freqDir = java.io.File("/sys/devices/system/cpu/cpu0/cpufreq/")
      if (freqDir.exists()) {
        maxFreq = java.io.File(freqDir, "cpuinfo_max_freq").readText().trim().toLongOrNull() ?: 0L
        minFreq = java.io.File(freqDir, "cpuinfo_min_freq").readText().trim().toLongOrNull() ?: 0L
      }
    } catch (_: Exception) {}
    val modelName = cpuInfo.split("\n").firstOrNull { it.startsWith("model name") || it.startsWith("Hardware") }
      ?.split(":")?.getOrNull(1)?.trim() ?: Build.HARDWARE
    return mapOf(
      "cores" to cores.toLong(),
      "model" to modelName,
      "maxFreqKHz" to maxFreq.toLong(),
      "minFreqKHz" to minFreq.toLong(),
      "abi" to Build.SUPPORTED_ABIS.joinToString(","),
    )
  }

  private fun getNetworkInfoBlock(): Map<String, Any?> {
    val interfaces = mutableListOf<Map<String, Any?>>()
    try {
      val enumeration = NetworkInterface.getNetworkInterfaces()
      Collections.list(enumeration).forEach { ni ->
        if (!ni.isUp || ni.isLoopback) return@forEach
        val hwAddr = ni.hardwareAddress?.joinToString(":") { "%02X".format(it) }
        val ipv4 = ni.interfaceAddresses.firstOrNull { it.address.hostAddress.contains(".") }?.address?.hostAddress
        val ipv6 = ni.interfaceAddresses.firstOrNull { it.address.hostAddress.contains(":") && !it.address.isLoopbackAddress }?.address?.hostAddress
        if (hwAddr != null || ipv4 != null || ipv6 != null) {
          interfaces.add(mapOf(
            "name" to ni.name,
            "displayName" to ni.displayName,
            "mac" to hwAddr,
            "ipv4" to ipv4,
            "ipv6" to ipv6,
            "mtu" to ni.mtu.toLong(),
          ))
        }
      }
    } catch (_: Exception) {}
    val telephony = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
    val simInfo = if (telephony != null && checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
      mapOf(
        "operator" to telephony.networkOperatorName,
        "operatorNumeric" to telephony.networkOperator,
        "simOperator" to telephony.simOperatorName,
        "phoneType" to telephony.phoneType.toLong(),
        "networkType" to telephony.networkType.toLong(),
      )
    } else {
      mapOf("note" to "READ_PHONE_STATE permission not granted")
    }
    return mapOf(
      "interfaces" to interfaces,
      "telephony" to simInfo,
    )
  }
}
