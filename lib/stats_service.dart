import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

import 'stats_db.dart';

/// Outcome of a CSV export.
///
/// Dismissing the save dialog is a decision, not a failure, so it gets its own
/// case — reporting it as an error taught people the button was broken.
enum ExportStatus { ok, cancelled, failed }

/// Where an export ended up, when it ended up anywhere.
class ExportResult {
  const ExportResult(this.status, [this.name]);

  final ExportStatus status;

  /// The name the document provider gave the file. Providers de-duplicate on
  /// collision, so this can differ from the name that was suggested.
  final String? name;
}

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

  /// Open this app's own "App info" screen.
  ///
  /// The way out of Android's restricted-settings block: the overflow menu
  /// there holds "Allow restricted settings", without which a sideloaded
  /// install cannot be given Usage access at all.
  static Future<void> openOwnAppInfo() async {
    try {
      await _channel.invokeMethod('openOwnAppInfo');
    } catch (e) {
      log('openOwnAppInfo error: $e');
    }
  }

  /// Open [url] in the device browser.
  ///
  /// Returns false when nothing handled it, so the caller can fall back to
  /// showing the address instead of silently doing nothing. Only https is
  /// accepted; the native side rejects anything else rather than letting a
  /// stray link turn into some other intent.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (e) {
      log('openUrl error: $e');
      return false;
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


  /// Hands [content] to the system save dialog under the suggested [filename].
  ///
  /// The user picks the destination, so the app never writes anywhere it was
  /// not pointed, and no storage permission is involved on any API level.
  /// Completes only once that dialog is dismissed one way or the other.
  static Future<ExportResult> exportCsv(
    String filename,
    String content, {
    String mime = 'text/csv',
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, Object?>('exportCsv', {
        'filename': filename,
        'content': content,
        'mime': mime,
      });
      switch (res?['status']) {
        case 'ok':
          return ExportResult(ExportStatus.ok, res?['name'] as String?);
        case 'cancelled':
          return const ExportResult(ExportStatus.cancelled);
        default:
          return const ExportResult(ExportStatus.failed);
      }
    } catch (e) {
      log('exportCsv error: $e');
      return const ExportResult(ExportStatus.failed);
    }
  }

  /// Opens the system screen where Usage access is granted.
  ///
  /// The permission is not a runtime one, so this is as far as any app can
  /// take the user — the switch itself is theirs to flip.
  static Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod('openUsageSettings');
    } catch (e) {
      log('openUsageSettings error: $e');
    }
  }

  /// Whether the user has agreed to background monitoring.
  ///
  /// Answers true for installs that predate onboarding but already hold Usage
  /// access — upgrading must not silently stop their collection.
  static Future<bool> hasMonitoringConsent() async {
    try {
      return await _channel.invokeMethod<bool>('getMonitoringConsent') ?? false;
    } catch (e) {
      log('getMonitoringConsent error: $e');
      // Fail closed: better to show onboarding twice than to monitor without it.
      return false;
    }
  }

  static Future<void> setMonitoringConsent(bool granted) async {
    try {
      await _channel.invokeMethod('setMonitoringConsent', {'granted': granted});
    } catch (e) {
      log('setMonitoringConsent error: $e');
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
