import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

import 'stats_db.dart';

/// Polls Android UsageStats for new foreground/background events and
/// accumulates them into the local SQLite store (source of truth).
class StatsService {
  const StatsService._();
  static const StatsService instance = StatsService._();

  static const MethodChannel _channel = MethodChannel('device_stats/usage');

  /// Overlap applied to the poll window so late-delivered UsageStats events
  /// are not permanently skipped. Safe because inserts are deduplicated.
  static const int _overlapMs = 5 * 60 * 1000;

  /// Whether the user has granted PACKAGE_USAGE_STATS (Usage Access).
  Future<bool> hasUsageAccess() async {
    try {
      final v = await _channel.invokeMethod<bool>('hasUsageAccess');
      return v ?? false;
    } catch (e) {
      log('hasUsageAccess error: $e');
      return false;
    }
  }

  /// Pull events newer than the last recorded marker and persist them.
  Future<int> sync() async {
    final last = await StatsDb.instance.getLastSyncTs();
    final since = last > _overlapMs ? last - _overlapMs : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final raw = await _channel.invokeListMethod<Map>('pollEvents', {
      'since': since,
    });
    if (raw == null || raw.isEmpty) {
      await StatsDb.instance.setLastSyncTs(now);
      return 0;
    }

    final events = raw.map((e) {
      return <String, Object?>{
        'package': e['package'],
        'event_type': (e['event_type'] as num).toInt(),
        'ts': (e['ts'] as num).toInt(),
      };
    }).toList();

    await StatsDb.instance.insertEvents(events);
    await StatsDb.instance.setLastSyncTs(now);
    return events.length;
  }

  /// Result of an aggregated query.
  static Future<List<Map<String, Object?>>> usageSince(int periodStartMs) =>
      StatsDb.instance.usageSince(periodStartMs);

  /// Fetch the app icon as base64-encoded PNG bytes (empty if unavailable).
  static Future<String> getAppIconBase64(String package) async {
    try {
      final res = await _channel.invokeMethod<String>('getAppIconBase64', {
        'package': package,
      });
      return res ?? '';
    } catch (e) {
      log('getAppIconBase64 error: $e');
      return '';
    }
  }

  /// Read battery/power fields from the platform fuel gauge.
  /// Returns null when unavailable. Keys: chargeFullUah, chargeCounterUah,
  /// currentNowUa, voltageNowUv (all nullable ints).
  static Future<Map?> readBatteryInfo() async {
    try {
      final res = await _channel.invokeMethod<Map>('readBatteryInfo');
      return res;
    } catch (e) {
      log('readBatteryInfo error: $e');
      return null;
    }
  }

  /// Fetch structured device info (model, screen, battery, storage, memory, CPU, network).
  static Future<Map?> getDeviceInfo() async {
    try {
      final res = await _channel.invokeMethod<Map>('getDeviceInfo');
      return res;
    } catch (e) {
      log('getDeviceInfo error: $e');
      return null;
    }
  }

  /// Open the system "App info" screen for a package.
  static Future<void> openAppInfo(String package) async {
    try {
      await _channel.invokeMethod('openAppInfo', {'package': package});
    } catch (e) {
      log('openAppInfo error: $e');
    }
  }

  /// Per-package network bytes since [sinceMs].
  ///
  /// Each entry has `package`, `rx_bytes` and `tx_bytes`. Empty when usage
  /// access has not been granted — the same grant this app already needs for
  /// usage events, so no extra prompt is involved.
  static Future<List<Map<String, Object?>>> networkUsage(int sinceMs) async {
    try {
      final rows = await _channel.invokeListMethod<Map>('networkUsage', {
        'since': sinceMs,
      });
      if (rows == null) return const [];
      return rows.map((r) => Map<String, Object?>.from(r)).toList();
    } catch (e) {
      log('networkUsage error: $e');
      return const [];
    }
  }

  /// Writes [content] into the shared Downloads folder.
  ///
  /// Returns the file name it actually landed under — MediaStore renames on
  /// collision rather than overwriting, so this can differ from [filename] —
  /// or null if the write failed.
  static Future<String?> exportToDownloads(
    String filename,
    String content, {
    String mime = 'text/csv',
  }) async {
    try {
      return await _channel.invokeMethod<String>('exportToDownloads', {
        'filename': filename,
        'content': content,
        'mime': mime,
      });
    } catch (e) {
      log('exportToDownloads error: $e');
      return null;
    }
  }

  /// Whether our notifications can be shown.
  ///
  /// The monitoring notification is the user's only signal that collection is
  /// running; on Android 13+ it is suppressed until POST_NOTIFICATIONS is
  /// granted, and the service gives no hint that this happened.
  static Future<bool> areNotificationsEnabled() async {
    try {
      final v = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return v ?? false;
    } catch (e) {
      log('areNotificationsEnabled error: $e');
      return false;
    }
  }

  /// Show the system notification-permission prompt.
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      log('requestNotificationPermission error: $e');
    }
  }

  /// Whether the system has exempted the app from battery optimisation.
  ///
  /// Without the exemption OEM power management — MediaTek's in particular —
  /// kills the collector after a while, which shows up as gaps in the history
  /// rather than as an obvious failure.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final v = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return v ?? false;
    } catch (e) {
      log('isIgnoringBatteryOptimizations error: $e');
      return false;
    }
  }

  /// Show the system dialog asking for that exemption. The user decides; the
  /// result is only observable by polling [isIgnoringBatteryOptimizations].
  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      log('requestIgnoreBatteryOptimizations error: $e');
    }
  }

  /// Whether the monitoring foreground service is live.
  static Future<bool> isServiceRunning() async {
    try {
      final v = await _channel.invokeMethod<bool>('isServiceRunning');
      return v ?? false;
    } catch (e) {
      log('isServiceRunning error: $e');
      return false;
    }
  }

  /// (Re)start the monitoring foreground service.
  static Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (e) {
      log('startForegroundService error: $e');
    }
  }

  /// Schedule the recurring background collector (AlarmManager).
  static Future<void> scheduleSync() async {
    try {
      await _channel.invokeMethod('scheduleSync');
    } catch (e) {
      log('scheduleSync error: $e');
    }
  }
}
