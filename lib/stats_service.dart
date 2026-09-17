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

  /// Schedule the recurring background collector (AlarmManager).
  static Future<void> scheduleSync() async {
    try {
      await _channel.invokeMethod('scheduleSync');
    } catch (e) {
      log('scheduleSync error: $e');
    }
  }
}
