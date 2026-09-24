import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:battery_plus/battery_plus.dart';
import 'stats_db.dart';
import 'stats_service.dart';
import 'solscan_service.dart';
import 'domains.dart';
import 'wallet_auth.dart';
import 'revoke.dart';
import 'theme.dart';
import 'widgets/boot_sequence.dart';
import 'widgets/crt_overlay.dart';
import 'l10n/app_localizations.dart';
import 'package:pipstats/widgets/tip_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialTheme = await _readInitialTheme();
  runApp(DeviceStatsApp(initialTheme: initialTheme));
}

Future<DeviceStatsTheme> _readInitialTheme() async {
  try {
    final v = await StatsDb.instance.getMeta('theme');
    final idx = int.tryParse(v ?? '');
    if (idx != null && idx >= 0 && idx < DeviceStatsTheme.values.length) {
      return DeviceStatsTheme.values[idx];
    }
  } catch (e) {
    log('_readInitialTheme error: $e');
  }
  return DeviceStatsTheme.pipboy;
}

/// Selectable UI palettes.
enum DeviceStatsTheme { pipboy, highContrast, light }

/// Lightweight app-wide scope carrying the active palette and a setter so the
/// header toggle can switch themes without prop drilling.
class DeviceStatsScope extends InheritedWidget {
  const DeviceStatsScope({
    required this.theme,
    required this.onThemeChanged,
    required super.child,
    super.key,
  });

  final DeviceStatsTheme theme;
  final ValueChanged<DeviceStatsTheme> onThemeChanged;

  static DeviceStatsScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DeviceStatsScope>();
    assert(scope != null, 'DeviceStatsScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(DeviceStatsScope oldWidget) =>
      theme != oldWidget.theme || onThemeChanged != oldWidget.onThemeChanged;
}

class DeviceStatsApp extends StatefulWidget {
  const DeviceStatsApp({required this.initialTheme, super.key});

  final DeviceStatsTheme initialTheme;

  @override
  State<DeviceStatsApp> createState() => _DeviceStatsAppState();
}

class _DeviceStatsAppState extends State<DeviceStatsApp> {
  late DeviceStatsTheme _theme = widget.initialTheme;

  /// False until the boot sequence finishes (or is tapped through). Held here
  /// rather than in HomePage so it runs once per cold start, not on rebuild.
  bool _booted = false;

  DeviceStatsColors get _colors => switch (_theme) {
    DeviceStatsTheme.pipboy => DeviceStatsColors.pipboy,
    DeviceStatsTheme.highContrast => DeviceStatsColors.highContrast,
    DeviceStatsTheme.light => DeviceStatsColors.light,
  };

  void _cycleTheme() {
    setState(() {
      _theme = DeviceStatsTheme
          .values[(_theme.index + 1) % DeviceStatsTheme.values.length];
    });
    StatsDb.instance.setMeta('theme', '${_theme.index}');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DEVICE STATS',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildDeviceStatsTheme(_colors),
      home: DeviceStatsScope(
        theme: _theme,
        onThemeChanged: (_) => _cycleTheme(),
        // The CRT layer wraps the whole app so scanlines and the vignette
        // cover dialogs and sheets too, not just the page body.
        child: CrtOverlay(
          child: _booted
              ? const HomePage()
              : BootSequence(onDone: () => setState(() => _booted = true)),
        ),
      ),
    );
  }
}

enum Period { day, week, month, all }

enum SortKey { time, launches }

/// Rows whose label or package matches [query], case-insensitively.
///
/// Matches the package name as well as the label so a user can find an app by
/// its id when two apps share a display name, which happens with clones and
/// work-profile copies.
List<Map<String, Object?>> filterRows(
  List<Map<String, Object?>> rows,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((r) {
    final label = (r['label'] as String? ?? '').toLowerCase();
    final pkg = (r['package'] as String? ?? '').toLowerCase();
    return label.contains(q) || pkg.contains(q);
  }).toList();
}

/// Escapes one CSV field.
///
/// Quotes whenever the value contains a comma, quote, or newline, and doubles
/// embedded quotes — app labels routinely contain commas, and an unescaped one
/// silently shifts every later column in the row.
String csvField(Object? value) {
  final s = value?.toString() ?? '';
  if (!s.contains(RegExp(r'[",\n\r]'))) return s;
  return '"${s.replaceAll('"', '""')}"';
}

/// Builds a CSV from [header] and [rows].
String buildCsv(List<String> header, List<List<Object?>> rows) {
  final buffer = StringBuffer()..writeln(header.map(csvField).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(csvField).join(','));
  }
  return buffer.toString();
}

/// Charge discharged across [samples], in µAh.
///
/// Sums only the drops between consecutive samples. A plain first-minus-last
/// would be wrong whenever the phone charged during the period: the counter
/// climbs back up and cancels out real earlier drain. Pairs where either
/// sample was taken on charger are skipped for the same reason.
///
/// Returns -1 when there is not enough history to measure anything, so the UI
/// can say so instead of showing a confident 0.
int drainBetween(List<Map<String, Object?>> samples) {
  if (samples.length < 2) return -1;
  var total = 0;
  var pairs = 0;
  for (var i = 1; i < samples.length; i++) {
    final prev = samples[i - 1];
    final cur = samples[i];
    if ((cur['charging'] as int? ?? 0) == 1 ||
        (prev['charging'] as int? ?? 0) == 1) {
      continue;
    }
    final a = prev['counter_uah'] as int? ?? 0;
    final b = cur['counter_uah'] as int? ?? 0;
    if (a <= 0 || b <= 0) continue;
    pairs++;
    if (a > b) total += a - b;
  }
  if (pairs == 0) return -1;
  return total;
}

/// Charge held in the battery, in µAh, at [level] out of [scale].
///
/// Returns -1 when the inputs cannot support an answer, so callers can fall
/// back rather than render a confident wrong number.
///
/// [capacityUah] is the capacity to scale against — design capacity here, not
/// the fuel gauge's own full reading. Kept pure and separate because every
/// battery defect in this file so far has been a unit or scale mistake that
/// looked right in the source.
int chargeAtLevel(int capacityUah, int level, int scale) {
  if (capacityUah <= 0 || level < 0 || scale <= 0) return -1;
  if (level > scale) return capacityUah;
  return (capacityUah * level / scale).round();
}

/// Pure comparator for usage rows: orders by foreground time or launches,
/// ascending or descending. Extracted for testability.
int compareUsageRows(
  Map<String, Object?> a,
  Map<String, Object?> b, {
  required SortKey key,
  required bool desc,
}) {
  final int cmp;
  if (key == SortKey.time) {
    cmp = (a['fg_ms'] as int).compareTo(b['fg_ms'] as int);
  } else {
    cmp = (a['launches'] as int).compareTo(b['launches'] as int);
  }
  return desc ? -cmp : cmp;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Battery _battery = Battery();
  static const MethodChannel _channel = MethodChannel('device_stats/usage');

  Period _period = Period.day;
  /// Monitoring health. Null until first checked, so the banner stays hidden
  /// rather than flashing a false alarm on the first frame.
  bool? _serviceRunning;
  bool? _batteryOptIgnored;
  bool? _notificationsEnabled;

  int _batteryLevel = -1;
  bool _charging = false;
  /// Charge currently in the battery, µAh. Recomputed on every sample so the
  /// metrics strip tracks the level instead of showing a fixed number.
  int _currentChargeUah = -1;

  int _capacityUah = -1;
  int _realCapacityUah = -1;
  int _designCapacityUah = -1;
  int _calibratedCapacityUah = -1;
  final List<int> _capacityEstimates = [];
  bool _batteryInfoAvailable = false;
  String _uptime = '';
  List<Map<String, Object?>> _rows = [];

  /// Live filter over [_rows]. Kept out of the query so typing never hits the
  /// database or disturbs the totals the percentages are computed against.
  String _appQuery = '';
  final _searchController = TextEditingController();

  /// [_rows] narrowed by [_appQuery].
  List<Map<String, Object?>> get _visibleRows => filterRows(_rows, _appQuery);
  bool _hasAccess = false;
  bool _syncing = false;
  bool _shortHistory = false;
  int _totalFgMs = 0;
  /// Discharge measured across the displayed period, µAh; -1 when there is
  /// not enough sample history yet to say.
  int _periodDrainUah = -1;
  final Map<String, String> _iconCache = {};
  final Map<String, String> _appLabels = {};
  SortKey _sortKey = SortKey.time;
  bool _sortDesc = true;
  Timer? _pollTimer;
  static const int _refreshInterval = 60;
  int _refreshCountdown = _refreshInterval;

  // Vault / on-chain state
  int _tab = 0; // 0 = SYSTEM, 1 = VAULT, 2 = SYSINFO, 3 = INFO
  int _vaultSection = 0; // 0 = tokens, 1 = nfts, 2 = tx, 3 = delegations
  Future<Map?>? _deviceInfoFuture;
  final TextEditingController _addressController = TextEditingController();
  String? _walletAddress;
  String? _walletLabel;
  bool _vaultBusy = false;
  bool _revokeBusy = false;
  int _solLamports = -1;
  double _totalUsd = 0;
  bool _pricesUnavailable = false;
  List<TokenAccountInfo> _tokenAccounts = [];
  List<AssetInfo> _assets = [];
  List<TxInfo> _txs = [];
  Map<String, TxDetail> _txDetails = {};
  String _vaultError = '';
  String _vaultSuccess = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
    _restoreWallet();
    _loadPrefs().then((_) => _refresh());
    _deviceInfoFuture = StatsService.getDeviceInfo();
    StatsService.scheduleSync();
    _refreshMonitoringHealth();
    _pollTimer = Timer.periodic(Duration(seconds: 1), (_) => _pollTick());
  }

  void _pollTick() {
    _refreshCountdown--;
    if (_refreshCountdown <= 0) {
      _refreshCountdown = _refreshInterval;
      _syncAndRefresh();
    }
    if (mounted) setState(() {});
  }

  void _resetRefreshTimer() {
    _refreshCountdown = _refreshInterval;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccess();
      _syncAndRefresh();
      // Both can change while we are away: the service may be killed by the
      // system, and the exemption is granted in a separate activity.
      _refreshMonitoringHealth();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _addressController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    final v = await StatsService.instance.hasUsageAccess();
    if (mounted) setState(() => _hasAccess = v);
  }

  Future<void> _loadPrefs() async {
    final period = await StatsDb.instance.getMeta('period');
    if (period != null && mounted) {
      final idx = int.tryParse(period);
      if (idx != null && idx >= 0 && idx < Period.values.length) {
        _period = Period.values[idx];
      }
    }
    final sortKey = await StatsDb.instance.getMeta('sort_key');
    if (sortKey != null && mounted) {
      final idx = int.tryParse(sortKey);
      if (idx != null && idx >= 0 && idx < SortKey.values.length) {
        _sortKey = SortKey.values[idx];
      }
    }
    final sortDesc = await StatsDb.instance.getMeta('sort_desc');
    if (sortDesc != null && mounted) {
      _sortDesc = sortDesc == '1';
    }
    final tab = await StatsDb.instance.getMeta('tab');
    if (tab != null && mounted) {
      _tab = int.tryParse(tab) ?? 0;
    }
    final calibrated = await StatsDb.instance.getMeta('battery_calibrated_capacity_uah');
    if (calibrated != null) {
      _calibratedCapacityUah = int.tryParse(calibrated) ?? -1;
    }
    // Load vault data from database if wallet is connected.
    if (_walletAddress != null) {
      try {
        final accounts = await StatsDb.instance.loadVaultTokenAccounts(_walletAddress!);
        final assets = await StatsDb.instance.loadVaultAssets(_walletAddress!);
        final txs = await StatsDb.instance.loadVaultTxs(_walletAddress!);
        if (mounted) {
          setState(() {
            _tokenAccounts = accounts
                .map((a) {
                      final info = TokenAccountInfo(
                        mint: a['mint'] as String,
                        owner: a['owner'] as String,
                        amount: a['amount'] as int,
                        delegate: a['delegate'] as String?,
                        state: a['state'] as int,
                        delegatedAmount: a['delegated_amount'] as int,
                        closeAuthority: a['close_authority'] as String?,
                        isNative: a['is_native'] == 1,
                        nativeAmount: a['native_amount'] as int,
                      );
                      info.pubkey = a['pubkey'] as String;
                      return info;
                    })
                .toList();
            _assets = assets
                .map((a) => AssetInfo(
                      id: a['id'] as String,
                      interface: a['interface'] as String,
                      name: a['name'] as String,
                      symbol: a['symbol'] as String,
                      balance: a['balance'] as String,
                      decimals: a['decimals'] as int,
                      burnt: a['burnt'] == 1,
                      compressed: a['compressed'] == 1,
                    ))
                .toList();
            _txs = txs
                .map((t) => TxInfo(
                      signature: t['signature'] as String,
                      slot: t['slot'] as int,
                      err: t['err'],
                      blockTime: t['block_time'] as int,
                      memo: t['memo'] as String?,
                    ))
                .toList();
          });
        }
      } catch (e) {
        log('Failed to load vault data: $e');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _manualRefresh() async {
    _resetRefreshTimer();
    await _syncAndRefresh();
    if (mounted) setState(() {});
  }

  /// Pull-to-refresh for the tabs. Also re-checks monitoring health, since a
  /// pull is exactly when someone is asking whether the data is current.
  /// Writes the usage table for the current period to Downloads as CSV.
  ///
  /// Exports what is on screen, including the drain estimate, so a row in the
  /// file can be traced back to a row in the app. Until this existed there was
  /// no way to get the history out at all — reinstalling the app destroyed it,
  /// which is how five days of it were lost during development.
  Future<void> _exportUsage() async {
    final l10n = AppLocalizations.of(context);
    if (_rows.isEmpty) {
      _toast(l10n.exportNothing);
      return;
    }
    final csv = buildCsv(
      const [
        'package',
        'label',
        'foreground_ms',
        'launches',
        'screen_pct',
        'drain_mah_estimate',
      ],
      _rows
          .map(
            (r) => [
              r['package'],
              r['label'],
              r['fg_ms'],
              r['launches'],
              (r['screen_pct'] as num?)?.toStringAsFixed(2),
              (r['drain_mah'] as num?)?.toStringAsFixed(1) ?? '',
            ],
          )
          .toList(),
    );
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp(r'[:T]'), '-');
    final saved = await StatsService.exportToDownloads(
      'pipstats-usage-$stamp.csv',
      csv,
    );
    if (!mounted) return;
    _toast(saved == null ? l10n.exportFailed : l10n.exportDone(saved));
  }

  void _toast(String message) {
    final ds = context.ds;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: ds.bg)),
        backgroundColor: ds.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pullRefresh() async {
    await _manualRefresh();
    await _refreshMonitoringHealth();
  }

  Future<void> _syncAndRefresh() async {
    if (_syncing) return;
    _syncing = true;
    try {
      try {
        await StatsService.instance.sync();
      } catch (e) {
        log('StatsService.sync error: $e');
      }
      await _readBattery();
      await _readUptime();
      await _loadRows();
      _deviceInfoFuture = StatsService.getDeviceInfo();
    } finally {
      _syncing = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _readBattery();
    await _readUptime();
    await _loadRows();
    if (mounted) setState(() {});
  }

  Future<void> _readBattery() async {
    try {
      final lvl = await _battery.batteryLevel;
      final charging = await _battery.batteryState;
      _batteryLevel = lvl;
      _charging =
          charging == BatteryState.charging || charging == BatteryState.full;
    } catch (e) {
      log('_readBattery error: $e');
    }
    await _sampleBattery();
  }

  Future<void> _sampleBattery() async {
    try {
      final info = await StatsService.readBatteryInfo();
      if (info == null) return;

      final designCap = info['designCapacityUah'];
      if (designCap is int && designCap > 0) {
        _designCapacityUah = designCap;
        StatsDb.instance.setMeta('battery_design_capacity_uah', '$designCap');
      } else {
        final cached = await StatsDb.instance.getMeta('battery_design_capacity_uah');
        if (cached != null) _designCapacityUah = int.tryParse(cached) ?? -1;
      }

      final counter = info['chargeCounterUah'];
      final scale = info['scale'];
      final level = info['level'];
      if (counter is int &&
          counter > 0 &&
          scale is int &&
          scale > 0 &&
          level is int &&
          level > 0) {
        final estimate = (counter * scale / level).round();
        _capacityEstimates.add(estimate);
        if (_capacityEstimates.length > 20) _capacityEstimates.removeAt(0);
        final sorted = [..._capacityEstimates]..sort();
        final mid = sorted.length ~/ 2;
        _realCapacityUah = sorted.length.isEven
            ? ((sorted[mid - 1] + sorted[mid]) / 2).round()
            : sorted[mid];
        StatsDb.instance.setMeta('battery_real_capacity_uah', '$_realCapacityUah');
      } else {
        final cached = await StatsDb.instance.getMeta('battery_real_capacity_uah');
        if (cached != null) _realCapacityUah = int.tryParse(cached) ?? -1;
      }

      final full = info['chargeFullUah'];
      if (full is int && full > 0) {
        _capacityUah = full;
        StatsDb.instance.setMeta('battery_capacity_uah', '$full');
      } else {
        final cached = await StatsDb.instance.getMeta('battery_capacity_uah');
        if (cached != null) _capacityUah = int.tryParse(cached) ?? -1;
      }

      if (counter is int && counter > 0) {
        // Persist the sample. StatsDb has carried this table and its queries
        // from the start, but nothing ever wrote to it, so per-app drain had
        // no measured discharge to work from.
        final currentUa = info['currentNowUa'];
        await StatsDb.instance.insertBatterySample(
          DateTime.now().millisecondsSinceEpoch,
          counter,
          currentUa is int ? currentUa : 0,
          _charging,
        );
      }

      // Charge held right now, as a fraction of the capacity we trust.
      //
      // The fraction comes from level/scale rather than from the gauge's
      // chargeCounter/chargeFull ratio: chargeFull is itself derived here as
      // counter * scale / level, so that ratio reduces to the same number
      // without adding precision.
      //
      // The absolute scale is the effective capacity (design, 4500 mAh on this
      // device) rather than the gauge's own full reading, which reports 2946
      // mAh for a cell with cycle_count 1 and no measured discharge.
      // Level comes from _batteryLevel — the same value the CHARGE cell
      // renders — so the two cells can never contradict each other. They are
      // read through different paths (battery_plus vs the native battery
      // intent) and were seen disagreeing outright under `dumpsys battery set
      // level`: CHARGE said 100% while this showed 43% worth of mAh.
      final charge = chargeAtLevel(
        _effectiveCapacityUah,
        _batteryLevel > 0
            ? _batteryLevel
            : (level is int && level > 0 ? level : -1),
        scale is int && scale > 0 ? scale : 100,
      );
      if (charge > 0) {
        _currentChargeUah = charge;
      } else if (counter is int && counter > 0) {
        _currentChargeUah = counter;
      }

      _batteryInfoAvailable = true;
    } catch (e) {
      log('_sampleBattery error: $e');
    }
  }

  /// Capacity to base the readout on, in µAh.
  ///
  /// Design capacity (from `power_profile.xml`) outranks anything derived from
  /// the fuel gauge. On this MediaTek device the gauge reports `charge_full` =
  /// 2946 mAh against a declared 4500 mAh — but `cycle_count` is 1, Android's
  /// min/last/max "learned" figures are all identical, and measured discharge
  /// is 0 mAh. A one-cycle cell has not lost 35%: that number is an
  /// uncalibrated gauge reading, not wear, so preferring it (as an earlier
  /// version of this getter did) showed a plainly wrong capacity.
  ///
  /// A user calibration still wins over both — that is a real measurement.
  int get _effectiveCapacityUah {
    if (_calibratedCapacityUah > 0) return _calibratedCapacityUah;
    if (_designCapacityUah > 0) return _designCapacityUah;
    if (_realCapacityUah > 0) return _realCapacityUah;
    if (_capacityUah > 0) return _capacityUah;
    return -1;
  }

  Future<void> _readUptime() async {
    try {
      final ms = await _channel.invokeMethod<int>('getUptimeMs');
      if (ms != null) {
        _uptime = _fmtUptime(ms / 1000.0);
      } else {
        _uptime = '...';
      }
    } catch (e) {
      log('_readUptime error: $e');
      _uptime = '...';
    }
  }

  String _fmtUptime(double sec) {
    final h = sec ~/ 3600;
    final d = h ~/ 24;
    final m = (sec ~/ 60) % 60;
    if (d > 0) return '${d}d ${h % 24}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  int _periodStartMs() {
    final now = DateTime.now();
    switch (_period) {
      case Period.day:
        return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      case Period.week:
        final dow = now.weekday;
        final start = now.subtract(Duration(days: dow - 1));
        return DateTime(
          start.year,
          start.month,
          start.day,
        ).millisecondsSinceEpoch;
      case Period.month:
        return DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      case Period.all:
        return 0;
    }
  }

  Future<void> _loadRows() async {
    final rows = await StatsService.usageSince(_periodStartMs());
    if (_appLabels.isEmpty) {
      try {
        final pm = await _channel.invokeListMethod<Map>('installedApps');
        if (pm != null) {
          for (final a in pm) {
            _appLabels[a['package'] as String] = (a['label'] as String?) ?? '';
          }
        }
      } catch (e) {
        log('_loadRows installedApps error: $e');
      }
    }
    final appList = rows.map((r) {
      final pkg = r['package'] as String;
      return <String, Object?>{
        'package': pkg,
        'label': _appLabels[pkg] ?? pkg,
        'fg_ms': r['fg_ms'],
        'launches': r['launches'],
      };
    }).toList();
    _sortRows(appList);
    // Sum total foreground time for the screen-time metric + bar scaling.
    _totalFgMs = 0;
    for (final r in appList) {
      _totalFgMs += (r['fg_ms'] as int?) ?? 0;
    }
    // Real discharge measured over the displayed period, apportioned by each
    // app's share of foreground time.
    //
    // This used to be `effectiveCapacity * share`: an app with half the screen
    // time was credited with half the battery's entire 4500 mAh, whatever the
    // phone had actually discharged — often nothing at all. That number was
    // unrelated to consumption by construction.
    //
    // It is still an estimate, and a crude one: Android exposes no per-app
    // power attribution to ordinary apps (BatteryStats needs DUMP), so screen
    // time is the only weighting available. What changed is that the total
    // being divided up is now a measurement rather than a constant.
    _periodDrainUah = drainBetween(
      await StatsDb.instance.batterySamplesBetween(
        _periodStartMs(),
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
    for (final r in appList) {
      final fg = (r['fg_ms'] as int?) ?? 0;
      final share = _totalFgMs > 0 ? fg / _totalFgMs : 0.0;
      r['screen_pct'] = share * 100.0;
      r['drain_mah'] = _periodDrainUah > 0
          ? (_periodDrainUah * share) / 1000.0
          : null;
    }
    var shortHistory = false;
    if (_period != Period.day && appList.isNotEmpty) {
      final start = _periodStartMs();
      final earliest = await StatsDb.instance.earliestEventTs();
      shortHistory = earliest != null && earliest > start;
    }
    if (!mounted) return;
    setState(() {
      _rows = appList;
      _shortHistory = shortHistory;
    });
  }

  void _sortRows(List<Map<String, Object?>> list) {
    list.sort((a, b) => compareUsageRows(a, b, key: _sortKey, desc: _sortDesc));
  }

  String _fmtDuration(int ms) {
    final s = ms ~/ 1000;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    if (h < 24) return '${h}h ${m % 60}m';
    final d = h ~/ 24;
    return '${d}d ${h % 24}h';
  }

  Future<void> _openUsageSettings() async {
    await _channel.invokeMethod('openUsageSettings');
    Future.delayed(const Duration(seconds: 1), _checkAccess);
  }

  void _cycleTheme() {
    DeviceStatsScope.of(context)
        .onThemeChanged(DeviceStatsScope.of(context).theme);
  }

  Future<void> _resetPackage(String pkg) async {
    await StatsDb.instance.resetPackage(pkg);
    await _loadRows();
  }

  Future<void> _resetGroup() async {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    final pkgs = await StatsDb.instance.allPackages();
    if (!mounted) return;
    final selected = <String>{};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ds.bg,
          title: Text(l10n.resetGroup, style: TextStyle(color: ds.primary)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView(
              children: pkgs.map((p) {
                return CheckboxListTile(
                  activeColor: ds.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p, style: TextStyle(color: ds.primary)),
                  value: selected.contains(p),
                  onChanged: (v) {
                    setDialogState(() {
                      if (v == true) {
                        selected.add(p);
                      } else {
                        selected.remove(p);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel, style: TextStyle(color: ds.dim)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (selected.isNotEmpty) {
                  StatsDb.instance.resetPackages(selected.toList());
                  _loadRows();
                }
              },
              child: Text(l10n.reset, style: TextStyle(color: ds.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _iconFor(String pkg) async {
    final cached = _iconCache[pkg];
    if (cached != null) return cached;
    final b64 = await StatsService.getAppIconBase64(pkg);
    if (_iconCache.length > 512) _iconCache.clear();
    _iconCache[pkg] = b64;
    return b64;
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ds.bg,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                _header(),
                _tabSwitch(),
                if (_tab == 0)
                  // The whole tab is one scroll view, not a fixed column with
                  // a scrolling list pinned at the bottom. RefreshIndicator
                  // only reacts to the scrollable under the finger, so with
                  // the metrics fixed above there was nowhere to pull from at
                  // the top of the screen.
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _pullRefresh,
                      color: ds.primary,
                      backgroundColor: ds.bg,
                      child: CustomScrollView(
                        // Always scrollable so the gesture works even when the
                        // content is shorter than the screen.
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _monitoringBanner(),
                                _metricsRow(),
                                _screenTimeBar(),
                                SizedBox(height: 12),
                                _periodSwitch(),
                                SizedBox(height: 6),
                                if (_shortHistory)
                                  Container(
                                    margin: EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ds.hintBg,
                                      border: Border.all(color: ds.dark),
                                    ),
                                    child: Text(
                                      l10n.shortHistory,
                                      style: TextStyle(
                                        color: ds.dim,
                                        fontSize: PipText.body,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                SizedBox(height: 12),
                                if (!_hasAccess) _accessHint(),
                                if (_hasAccess) _sortHeader(),
                                if (_hasAccess) _periodDrainLine(),
                                if (_hasAccess && _rows.isNotEmpty)
                                  _searchField(),
                              ],
                            ),
                          ),
                          if (_visibleRows.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Text(
                                    _rows.isEmpty
                                        ? l10n.noDataYet
                                        : l10n.searchNoMatch,
                                    style: TextStyle(
                                      color: ds.dim,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverList.builder(
                              itemCount: _visibleRows.length,
                              itemBuilder: (ctx, i) => _appRow(i),
                            ),
                        ],
                      ),
                    ),
                  )
                else if (_tab == 1)
                  Expanded(child: _vaultTab())
                else if (_tab == 2)
                  Expanded(child: _sysInfoTab())
                else
                  Expanded(child: _infoTab()),
              ],
            ),
          ),
          // Scanlines are drawn by CrtOverlay, which is palette-aware and
          // wraps the whole app including dialogs. A second _Scanlines layer
          // used to sit here and drew on every palette, including the light
          // and high-contrast ones that are meant to stay clean.
        ],
      ),
    );
  }

  // ---- Header (Pip-Boy title bar) ----
  Widget _header() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ds.dark,
        border: Border(bottom: BorderSide(color: ds.primary, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.headerTitle,
                maxLines: 1,
                style: TextStyle(
                  color: ds.primary,
                  fontSize: PipText.hero,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          _cornerButton(Icons.palette_outlined, _cycleTheme),
          _cornerButton(Icons.download_outlined, _exportUsage),
          _cornerButton(Icons.refresh, _manualRefresh),
          _cornerButton(Icons.delete_sweep, _resetGroup),
          _cornerButton(Icons.attach_money_outlined, _showTipModal),
        ],
      ),
    );
  }

  /// A header button.
  ///
  /// Sized to [_touchTarget], the Material minimum. It used to come out at
  /// about 29dp — roughly 60% of the minimum — which is a real miss rate, not
  /// a matter of taste. The title beside these is in a FittedBox and simply
  /// renders smaller to make room.
  Widget _cornerButton(IconData icon, VoidCallback onTap) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: EdgeInsets.only(left: 6),
        width: _touchTarget,
        height: _touchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: ds.primary, width: 1),
          color: ds.dark,
        ),
        child: Icon(icon, color: ds.primary, size: 24),
      ),
    );
  }

  /// Material's minimum touch target.
  static const double _touchTarget = 48;

  // ---- Tab switch (SYSTEM / VAULT / SYSINFO / INFO) ----
  Widget _tabSwitch() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _tabButton(l10n.systemTab, 0),
          SizedBox(width: 6),
          _tabButton(l10n.vaultTab, 1),
          SizedBox(width: 6),
          _tabButton(l10n.sysInfoTab, 2),
          SizedBox(width: 6),
          _tabButton(l10n.infoTab, 3),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int idx) {
    final ds = context.ds;
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _tab = idx);
          StatsDb.instance.setMeta('tab', '$idx');
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? ds.primary : Colors.transparent,
            border: Border.all(color: ds.primary, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? ds.bg : ds.primary,
              fontSize: PipText.note,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ---- Vault tab (on-chain security) ----
  Widget _vaultTab() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    // The wallet panel above stays put, so the pull has to start over the
    // list below it. Making this tab one scroll view would mean restructuring
    // the connect flow and its four sub-tabs, which is a separate job.
    return RefreshIndicator(
      onRefresh: () async {
        if (_walletAddress != null) await _loadVaultData();
      },
      color: ds.primary,
      backgroundColor: ds.bg,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wallet address entry + scan header
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ds.panel,
            border: Border.all(color: ds.primary, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.seedVault,
                style: TextStyle(
                  color: ds.primary,
                  fontSize: PipText.heading,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              if (_walletAddress == null) ...[
                Text(
                  l10n.connectSeedVault,
                  style: TextStyle(color: ds.dim, fontSize: PipText.body),
                ),
                SizedBox(height: 10),
                _vaultActionButton(
                  l10n.connectSeedVaultBtn,
                  _vaultBusy,
                  _authorize,
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _addressController,
                  style: TextStyle(color: ds.primary, fontSize: PipText.body),
                  decoration: InputDecoration(
                    hintText: l10n.addressHint,
                    hintStyle: TextStyle(color: ds.dark, fontSize: PipText.body),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: ds.dark, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: ds.primary, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                _vaultActionButton(l10n.scanWallet, _vaultBusy, _scanManual),
              ] else ...[
                Text(
                  l10n.addrLabel(_walletAddress!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ds.primary, fontSize: PipText.body),
                ),
                if (_walletLabel != null)
                  Text(
                    l10n.walletLabel(_walletLabel!),
                    style: TextStyle(color: ds.dim, fontSize: PipText.label),
                  ),
                SizedBox(height: 8),
                Text(
                  l10n.solBalance(
                    _solLamports < 0
                        ? '...'
                        : '${(_solLamports / 1e9).toStringAsFixed(4)} SOL',
                  ),
                  style: TextStyle(color: ds.primary, fontSize: PipText.value),
                ),
                if (_totalUsd > 0)
                  Text(
                    l10n.estValue(_totalUsd.toStringAsFixed(2)),
                    style: TextStyle(color: ds.dim, fontSize: PipText.body),
                  ),
                if (_pricesUnavailable)
                  Text(
                    l10n.pricesUnavailable,
                    style: TextStyle(color: ds.dim, fontSize: PipText.label),
                  ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _vaultActionButton(
                        l10n.rescan,
                        _vaultBusy,
                        _loadVaultData,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _vaultActionButton(
                        l10n.remove,
                        false,
                        _removeWallet,
                      ),
                    ),
                  ],
                ),
              ],
              if (_vaultError.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    _vaultError,
                    style: TextStyle(color: ds.dangerBorder, fontSize: PipText.label),
                  ),
                ),
              if (_vaultSuccess.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    _vaultSuccess,
                    style: TextStyle(color: ds.primary, fontSize: PipText.label),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 10),

        // Sub-tabs: TOKENS / NFT / TX / DELEGATIONS
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Row(
            children: [
              _vaultTabButton(l10n.tabTokens, 0),
              SizedBox(width: 6),
              _vaultTabButton(l10n.tabNfts, 1),
              SizedBox(width: 6),
              _vaultTabButton(l10n.tabTx, 2),
              SizedBox(width: 6),
              _vaultTabButton(l10n.tabDelegations, 3),
            ],
          ),
        ),
        SizedBox(height: 10),

        // Active section (scrollable)
        Expanded(child: _activeVaultSection()),

        // Privacy policy
        _privacySection(),
      ],
      ),
    );
  }

  Widget _vaultTabButton(String label, int idx) {
    final ds = context.ds;
    final active = _vaultSection == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _vaultSection = idx),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? ds.primary : Colors.transparent,
            border: Border.all(color: ds.primary, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? ds.bg : ds.primary,
              fontSize: PipText.body,
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeVaultSection() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    switch (_vaultSection) {
      case 0:
        return ListView(
          children: [
            Text(
              l10n.tokens,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.heading,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6),
            ..._buildTokenList(),
          ],
        );
      case 1:
        return ListView(
          children: [
            Text(
              l10n.nfts,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.heading,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6),
            ..._buildNftList(),
          ],
        );
      case 2:
        return ListView(
          children: [
            Text(
              l10n.transactions,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.heading,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6),
            ..._buildTxList(),
          ],
        );
      case 3:
        return ListView(
          children: [
            Text(
              l10n.delegations,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.heading,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6),
            if (_walletAddress == null)
              Text(
                l10n.connectWalletToScan,
                style: TextStyle(color: ds.dim, fontSize: PipText.body),
              )
            else if (_tokenAccounts.isEmpty && _vaultBusy)
              Text(l10n.scanning, style: TextStyle(color: ds.dim, fontSize: PipText.body))
            else if (_tokenAccounts.isEmpty)
              Text(
                l10n.noActiveDelegations,
                style: TextStyle(color: ds.dim, fontSize: PipText.body),
              )
            else ...[
              // A wallet can hold token accounts and still have no approvals;
              // the previous `else` branch rendered an empty list in that case
              // and the "none" message never appeared.
              if (_delegatedAccounts.isEmpty)
                Text(
                  l10n.noActiveDelegations,
                  style: TextStyle(color: ds.dim, fontSize: PipText.body),
                )
              else ...[
                _delegationAlert(ds, l10n, _delegatedAccounts.length),
                SizedBox(height: 8),
                ..._delegatedAccounts.map((t) => _delegationRow(t)),
              ],
            ],
            SizedBox(height: 14),
            Text(
              l10n.closeAuthority,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.heading,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6),
            ..._buildCloseAuthorityList(),
            SizedBox(height: 14),
            _revokeSection(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildTokenList() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    if (_walletAddress == null) return [];
    final tokens = _assets
        .where((a) => a.isFungible && a.uiAmount != '0')
        .toList();
    if (tokens.isEmpty && !_vaultBusy) {
      return [
        Text(l10n.noTokens, style: TextStyle(color: ds.dim, fontSize: PipText.body)),
      ];
    }
    return tokens.map((a) {
      final sym = a.symbol.isNotEmpty
          ? a.symbol
          : (a.name.isNotEmpty ? a.name : a.id);
      return Container(
        margin: EdgeInsets.only(bottom: 4),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ds.panel,
          border: Border.all(color: ds.dark, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sym,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ds.primary, fontSize: PipText.body),
              ),
            ),
            Text(a.uiAmount, style: TextStyle(color: ds.primary, fontSize: PipText.body)),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildNftList() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    if (_walletAddress == null) return [];
    final nfts = _assets.where((a) => !a.isFungible && !a.burnt).toList();
    final spamCount = _assets.where((a) => !a.isFungible && a.burnt).length;
    if (nfts.isEmpty && !_vaultBusy) {
      return [Text(l10n.noNfts, style: TextStyle(color: ds.dim, fontSize: PipText.body))];
    }
    // Cap display to avoid a huge list; show count + first several names.
    final count = nfts.length;
    final shown = nfts.take(20).toList();
    final widgets = <Widget>[];
    for (final a in shown) {
      final name = a.name.isNotEmpty
          ? a.name
          : (a.symbol.isNotEmpty ? a.symbol : l10n.unnamed);
      widgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: 2),
          child: Text('• $name', style: TextStyle(color: ds.dim, fontSize: PipText.label)),
        ),
      );
    }
    if (count > shown.length) {
      widgets.add(
        Text(
          l10n.moreCount(count - shown.length),
          style: TextStyle(color: ds.dark, fontSize: PipText.label),
        ),
      );
    }
    if (spamCount > 0) {
      widgets.add(
        Text(
          l10n.spamHidden(spamCount),
          style: TextStyle(
            color: ds.dangerText,
            fontSize: PipText.note,
            letterSpacing: 1,
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildCloseAuthorityList() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    if (_walletAddress == null) return [];
    final risky = _tokenAccounts
        .where((t) => !t.hasDelegate && t.hasCloseAuthority)
        .toList();
    if (risky.isEmpty && !_vaultBusy) {
      return [
        Text(
          l10n.noCloseAuthorityRisks,
          style: TextStyle(color: ds.dim, fontSize: PipText.body),
        ),
      ];
    }
    return risky.map((t) {
      return Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ds.dangerBg,
          border: Border.all(color: ds.dangerBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.accountLabel(t.pubkey),
              style: TextStyle(
                color: ds.dangerText,
                fontSize: PipText.note,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 4),
            Text(
              l10n.closeAuthorityLabel(t.closeAuthority ?? ''),
              style: TextStyle(
                color: ds.dangerTextStrong,
                fontSize: PipText.note,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 4),
            Text(
              l10n.closeAuthorityWarning,
              style: TextStyle(color: ds.dim, fontSize: PipText.label),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildTxList() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    if (_walletAddress == null) return [];
    if (_txs.isEmpty && !_vaultBusy) {
      return [
        Text(
          l10n.noTransactions,
          style: TextStyle(color: ds.dim, fontSize: PipText.body),
        ),
      ];
    }
    return _txs.map((t) {
      final timeStr = t.blockTime > 0
          ? _formatBlockTime(t.blockTime)
          : l10n.txSlot(t.slot);
      final sig = t.signature.length > 16
          ? '${t.signature.substring(0, 16)}…'
          : t.signature;
      final color = t.hasError ? ds.dangerTextStrong : ds.primary;
      final status = t.hasError ? l10n.statusFailed : l10n.statusOk;
      final detail = _txDetails[t.signature];

      final lines = <Widget>[
        Text(
          l10n.txStatusSig(status, sig),
          style: TextStyle(color: color, fontSize: PipText.label, letterSpacing: 1),
        ),
        Text(
          '        $timeStr',
          style: TextStyle(color: ds.dim, fontSize: PipText.note),
        ),
      ];

      if (detail != null) {
        // Fee
        if (detail.feeLamports > 0) {
          lines.add(
            Text(
              l10n.feeSol(detail.feeSol),
              style: TextStyle(color: ds.dim, fontSize: PipText.note),
            ),
          );
        }
        // Program labels (deduplicated)
        if (detail.programLabels.isNotEmpty) {
          lines.add(
            Text(
              l10n.protoLabel(detail.programLabels.join(', ')),
              style: TextStyle(color: ds.dim, fontSize: PipText.note),
            ),
          );
        }
        // SOL (native) transfers
        for (final sol in detail.solTransfers) {
          final dest = _shortAddr(sol.destination);
          lines.add(
            Text(
              l10n.solTransfer(dest, sol.solAmount),
              style: TextStyle(color: ds.dim, fontSize: PipText.note),
            ),
          );
        }
        // SPL token transfers
        for (final tr in detail.transfers) {
          final dest = _shortAddr(tr.destination);
          lines.add(
            Text(
              l10n.tokenTransfer(dest, tr.amount),
              style: TextStyle(color: ds.dim, fontSize: PipText.note),
            ),
          );
        }
      }

      return Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      );
    }).toList();
  }

  String _shortAddr(String address) {
    if (address.isEmpty) return '?';
    return address.length > 12 ? '${address.substring(0, 12)}…' : address;
  }

  String _formatBlockTime(int unixSeconds) {
    final l10n = AppLocalizations.of(context);
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.timeJustNow;
    if (diff.inHours < 1) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.timeHoursAgo(diff.inHours);
    return l10n.timeDaysAgo(diff.inDays);
  }

  /// Token accounts with an active delegate — the approvals a user should
  /// review and revoke.
  List<TokenAccountInfo> get _delegatedAccounts =>
      _tokenAccounts.where((t) => t.hasDelegate).toList();

  /// Prominent warning that approvals exist. Listing them further down is not
  /// enough: an approval lets a third party move tokens without asking again,
  /// so it has to be visible without scrolling.
  Widget _delegationAlert(
    DeviceStatsColors ds,
    AppLocalizations l10n,
    int count,
  ) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: ds.dangerBg,
        border: Border.all(color: ds.dangerBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.delegationAlertTitle,
            style: TextStyle(
              color: ds.dangerTextStrong,
              fontSize: PipText.note,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 4),
          Text(
            l10n.delegationAlertBody(count),
            style: TextStyle(color: ds.dangerText, fontSize: PipText.body),
          ),
        ],
      ),
    );
  }

  Widget _delegationRow(TokenAccountInfo t) {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ds.dangerBg,
        border: Border.all(color: ds.dangerBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.accountLabel(t.pubkey),
            style: TextStyle(
              color: ds.dangerText,
              fontSize: PipText.note,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 4),
          Text(
            l10n.mintLabel(t.mint),
            style: TextStyle(
              color: ds.dangerText,
              fontSize: PipText.label,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 4),
          Text(
            l10n.delegateLabel(t.delegate ?? ''),
            style: TextStyle(
              color: ds.dangerTextStrong,
              fontSize: PipText.note,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 4),
          Text(
            l10n.approvedAmountLabel(t.delegatedAmount),
            style: TextStyle(color: ds.primary, fontSize: PipText.body),
          ),
          SizedBox(height: 8),
          _vaultActionButton('REVOKE', _revokeBusy, () => _revokeDelegation(t)),
        ],
      ),
    );
  }

  Future<void> _revokeDelegation(TokenAccountInfo t) async {
    final l10n = AppLocalizations.of(context);
    if (_walletAddress == null) return;
    setState(() {
      _revokeBusy = true;
      _vaultError = '';
      _vaultSuccess = '';
    });
    try {
      final sig = await RevokeService.instance.revoke(
        ownerAddress: _walletAddress!,
        tokenAccount: t.pubkey,
      );
      if (!mounted) return;
      setState(() {
        _revokeBusy = false;
        _vaultError = '';
      });
      // Rescan delegations to reflect the change.
      await _loadVaultData();
      // Surface a success note.
      if (!mounted) return;
      setState(() {
        _vaultSuccess = l10n.revokedOk('${sig.substring(0, 16)}…');
      });
      await Future.delayed(Duration(seconds: 4));
      if (mounted) {
        setState(() => _vaultSuccess = '');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _revokeBusy = false;
        _vaultError = l10n.revokeError(e);
      });
    }
  }

  Widget _revokeSection() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ds.panel,
        border: Border.all(color: ds.dark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.revokeSection,
            style: TextStyle(color: ds.primary, fontSize: PipText.heading, letterSpacing: 2),
          ),
          SizedBox(height: 6),
          Text(
            l10n.revokeClearsHint,
            style: TextStyle(color: ds.dim, fontSize: PipText.label, letterSpacing: 1),
          ),
          SizedBox(height: 4),
          Text(
            l10n.revokeDisclaimer,
            style: TextStyle(color: ds.dim, fontSize: PipText.label),
          ),
        ],
      ),
    );
  }

  Widget _privacySection() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ds.panel,
        border: Border.all(color: ds.dark, width: 1),
      ),
      child: GestureDetector(
        onTap: _showPrivacy,
        child: Row(
          children: [
            Text(
              l10n.privacy,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.heading,
                letterSpacing: 2,
              ),
            ),
            Spacer(),
            Text(l10n.tapToView, style: TextStyle(color: ds.dim, fontSize: PipText.body)),
          ],
        ),
      ),
    );
  }

  void _showPrivacy() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.bg,
        title: Text(
          l10n.privacyPolicy,
          style: TextStyle(color: ds.primary, fontSize: PipText.heading),
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n.privacyBody,
            style: TextStyle(color: ds.dim, fontSize: PipText.body),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.close, style: TextStyle(color: ds.primary)),
          ),
        ],
      ),
    );
  }

  Widget _vaultActionButton(String label, bool busy, VoidCallback onTap) {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: busy ? ds.dark : ds.primary,
          border: Border.all(color: ds.primary, width: 1),
        ),
        child: Text(
          busy ? l10n.pleaseWait : label,
          style: TextStyle(
            color: busy ? ds.primary : ds.bg,
            fontSize: PipText.body,
            letterSpacing: 1,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _authorize() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _vaultBusy = true;
      _vaultError = '';
    });
    try {
      final auth = await WalletAuthService.instance.authorize();
      if (!mounted) return;
      if (auth == null) {
        setState(() {
          _vaultBusy = false;
          _vaultError = l10n.seedVaultUnavailable;
        });
        return;
      }
      setState(() {
        _walletAddress = auth.address;
        _walletLabel = auth.accountLabel;
        _vaultBusy = false;
      });
      await _loadVaultData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vaultBusy = false;
        _vaultError = l10n.authError(e);
      });
    }
  }

  Future<void> _scanManual() async {
    final l10n = AppLocalizations.of(context);
    final input = _addressController.text.trim();
    if (WalletAuthService.isSkrDomain(input)) {
      setState(() {
        _vaultBusy = true;
        _vaultError = '';
      });
      String? address;
      try {
        address = await SkrResolver.instance.resolve(input);
      } catch (e) {
        log('SkrResolver error: $e');
        address = null;
      }
      if (!mounted) return;
      if (address == null) {
        setState(() {
          _vaultBusy = false;
          _vaultError = l10n.domainNotFound;
        });
        return;
      }
      setState(() {
        _walletAddress = address;
        _walletLabel = input;
        _vaultBusy = false;
        _vaultError = '';
      });
      await _loadVaultData();
      return;
    }
    final auth = WalletAuthService.instance.fromManual(input);
    if (auth == null) {
      setState(() {
        _vaultError = l10n.invalidAddress;
      });
      return;
    }
    setState(() {
      _walletAddress = auth.address;
      _walletLabel = auth.accountLabel;
      _vaultError = '';
    });
    await _loadVaultData();
  }

  Future<void> _loadVaultData() async {
    final l10n = AppLocalizations.of(context);
    final addr = _walletAddress;
    if (addr == null) return;
    setState(() {
      _vaultBusy = true;
      _vaultError = '';
    });
    try {
      final (lamports, accounts, assets, txs) = await (
        SolScanService.instance.getBalanceLamports(addr),
        SolScanService.instance.scanDelegates(addr),
        SolScanService.instance.getAssets(addr),
        SolScanService.instance.getSignatures(addr, limit: 10),
      ).wait;
      // Estimate portfolio value from Jupiter prices (best-effort).
      final mints = <String>[
        SolScanService.solMint,
        ...assets.where((a) => a.isFungible).map((a) => a.id),
      ];
      final prices = await SolScanService.instance.getPrices(mints);
      final totalUsd = prices == null
          ? 0.0
          : _estimateUsd(lamports, assets, prices);
      if (!mounted) return;
      setState(() {
        _solLamports = lamports;
        _totalUsd = totalUsd;
        _pricesUnavailable = prices == null;
        _tokenAccounts = accounts;
        _assets = assets;
        _txs = txs;
        _vaultBusy = false;
      });
      // Persist vault data to database.
      try {
        await StatsDb.instance.saveVaultTokenAccounts(addr, accounts
            .map((a) => {
                  'pubkey': a.pubkey,
                  'mint': a.mint,
                  'owner': a.owner,
                  'amount': a.amount,
                  'delegate': a.delegate,
                  'state': a.state,
                  'delegatedAmount': a.delegatedAmount,
                  'closeAuthority': a.closeAuthority,
                  'isNative': a.isNative,
                  'nativeAmount': a.nativeAmount,
                })
            .toList());
        await StatsDb.instance.saveVaultAssets(addr, assets
            .map((a) => {
                  'id': a.id,
                  'interface': a.interface,
                  'name': a.name,
                  'symbol': a.symbol,
                  'balance': a.balance,
                  'decimals': a.decimals,
                  'burnt': a.burnt,
                  'compressed': a.compressed,
                })
            .toList());
        await StatsDb.instance.saveVaultTxs(addr, txs
            .map((t) => {
                  'signature': t.signature,
                  'slot': t.slot,
                  'err': t.err,
                  'blockTime': t.blockTime,
                  'memo': t.memo,
                })
            .toList(), {
          for (var e in _txDetails.entries)
            e.key: {
              'feeLamports': e.value.feeLamports,
              'programs': e.value.programs,
              'transfers': e.value.transfers.map((t) => {
                    'mint': t.mint,
                    'amount': t.amount,
                    'destination': t.destination,
                    'source': t.source,
                  }).toList(),
              'solTransfers': e.value.solTransfers.map((t) => {
                    'destination': t.destination,
                    'source': t.source,
                    'lamports': t.lamports,
                  }).toList(),
            }
        });
      } catch (e) {
        log('Failed to save vault data: $e');
      }
      // Enrich first several transactions with fee/program/transfer details.
      final details = <String, TxDetail>{};
      final toFetch = txs.take(5).toList();
      final fetched = await Future.wait(
        toFetch.map((t) async {
          try {
            final d = await SolScanService.instance.getTransactionDetail(
              t.signature,
            );
            return MapEntry(t.signature, d);
          } catch (e) {
            log('getTransactionDetail error: $e');
            return null;
          }
        }),
      );
      for (final e in fetched) {
        if (e != null) details[e.key] = e.value;
      }
      if (mounted) {
        setState(() => _txDetails = details);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vaultError = l10n.scanError(e);
        _vaultBusy = false;
      });
    }
  }

  Future<void> _removeWallet() async {
    final addr = _walletAddress;
    await WalletAuthService.instance.deauthorize();
    if (addr != null) {
      await StatsDb.instance.deleteVaultData(addr);
    }
    if (!mounted) return;
    setState(() {
      _walletAddress = null;
      _walletLabel = null;
      _solLamports = -1;
      _totalUsd = 0;
      _pricesUnavailable = false;
      _tokenAccounts = [];
      _assets = [];
      _txs = [];
      _vaultError = '';
      _vaultSuccess = '';
      _vaultBusy = false;
      _addressController.clear();
    });
  }

  double _estimateUsd(
    int lamports,
    List<AssetInfo> assets,
    Map<String, double> prices,
  ) {
    double total = 0;
    final solPrice = prices[SolScanService.solMint] ?? 0;
    if (lamports > 0) total += (lamports / 1e9) * solPrice;
    for (final a in assets.where((a) => a.isFungible)) {
      final price = prices[a.id] ?? 0;
      final balance = int.tryParse(a.balance);
      if (price > 0 && balance != null) {
        var units = balance.toDouble();
        if (a.decimals > 0) units /= _pow10(a.decimals);
        total += units * price;
      }
    }
    return total;
  }

  static double _pow10(int e) {
    var v = 1.0;
    for (int i = 0; i < e; i++) {
      v *= 10;
    }
    return v;
  }

  Future<void> _restoreWallet() async {
    final auth = await WalletAuthService.instance.lastKnownWallet();
    if (auth != null && mounted) {
      setState(() {
        _walletAddress = auth.address;
        _walletLabel = auth.accountLabel;
      });
    }
  }

  // ---- Monitoring health ----

  /// Shown only when background collection is degraded.
  ///
  /// Two distinct problems, in order of severity: the service is not running
  /// at all, or it is running but the OEM power manager is free to kill it.
  /// Nothing is drawn when both are fine — a permanent nag trains people to
  /// ignore the one time it matters.
  Widget _monitoringBanner() {
    final l10n = AppLocalizations.of(context);
    final ds = context.ds;

    // Ordered by severity. Blocked notifications come first: the service can
    // be running perfectly and the user would still have no sign of it.
    final stopped = _serviceRunning == false;
    final noNotif = !stopped && _notificationsEnabled == false;
    final unprotected =
        !stopped && !noNotif && _batteryOptIgnored == false;
    if (!stopped && !noNotif && !unprotected) {
      return const SizedBox.shrink();
    }

    final String message;
    final String action;
    final VoidCallback onPressed;
    if (stopped) {
      message = l10n.monitoringStopped;
      action = l10n.monitoringRestart;
      onPressed = _restartMonitoring;
    } else if (noNotif) {
      message = l10n.monitoringNoNotif;
      action = l10n.monitoringEnableNotif;
      onPressed = _requestNotifications;
    } else {
      message = l10n.monitoringBatteryOpt;
      action = l10n.monitoringAllow;
      onPressed = _requestBatteryExemption;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: ds.dangerBg,
          border: Border.all(color: ds.dangerBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stopped)
              Text(
                l10n.monitoringTitle,
                style: TextStyle(
                  color: ds.dangerTextStrong,
                  fontSize: PipText.note,
                  letterSpacing: 1,
                ),
              ),
            SizedBox(height: stopped ? 4 : 0),
            Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: ds.dangerText,
                      fontSize: PipText.note,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                TextButton(
                  onPressed: onPressed,
                  child: Text(
                    action,
                    style: TextStyle(
                      color: ds.dangerTextStrong,
                      fontSize: PipText.note,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshMonitoringHealth() async {
    final running = await StatsService.isServiceRunning();
    final ignored = await StatsService.isIgnoringBatteryOptimizations();
    final notif = await StatsService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _batteryOptIgnored = ignored;
      _notificationsEnabled = notif;
    });
  }

  Future<void> _restartMonitoring() async {
    await StatsService.startForegroundService();
    await StatsService.scheduleSync();
    await _refreshMonitoringHealth();
  }

  Future<void> _requestNotifications() async {
    await StatsService.requestNotificationPermission();
    await _refreshMonitoringHealth();
  }

  Future<void> _requestBatteryExemption() async {
    await StatsService.requestIgnoreBatteryOptimizations();
    // The system dialog is a separate activity; re-check when we come back.
    await _refreshMonitoringHealth();
  }

  // ---- Metrics row ----
  Widget _metricsRow() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _metricBlock(
            l10n.charge,
            _batteryLevel < 0
                ? '...'
                : '$_batteryLevel%${_charging ? ' *' : ''}',
          ),
          SizedBox(width: 12),
          _metricBlock(l10n.uptime, _uptime.isEmpty ? '...' : _uptime),
          if (_batteryInfoAvailable) ...[
            SizedBox(width: 12),
            // Charge now over total, so the cell moves with the battery
            // instead of showing one fixed number. FittedBox in _metricBlock
            // shrinks it rather than wrapping to a second line.
            _metricBlock(
              l10n.batteryCapacity,
              _effectiveCapacityUah > 0 && _currentChargeUah > 0
                  ? '${(_currentChargeUah / 1000.0).round()}'
                      ' / ${(_effectiveCapacityUah / 1000.0).round()} mAh'
                  : _effectiveCapacityUah > 0
                      ? '${(_effectiveCapacityUah / 1000.0).round()} mAh'
                      : '...',
              onLongPress: _effectiveCapacityUah > 0 ? _showCalibrationDialog : null,
            ),
          ],
        ],
      ),
    );
  }

  /// One cell of the metrics strip.
  ///
  /// The label and the value used to share [PipText.heading], which made both
  /// wrap to two lines once the type scale went up — "BATTERY CAPACITY" and
  /// "4500 / 4500 mAh" each took two rows and the strip ate a third of the
  /// screen. The label is now small and the value is kept to a single line,
  /// shrinking to fit rather than wrapping.
  Widget _metricBlock(String label, String value, {VoidCallback? onLongPress}) {
    final ds = context.ds;
    return Expanded(
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: ds.panel,
            border: Border.all(color: ds.dark, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ds.dim,
                  fontSize: PipText.note,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: ds.primary,
                    fontSize: PipText.title,
                    shadows: ds.crt ? pipGlow(ds.primary, blur: 5) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Screen time summary bar ----
  Widget _screenTimeBar() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ds.panel,
          border: Border.all(color: ds.primary, width: 1),
        ),
        child: Row(
          children: [
            Text(
              l10n.screenTime,
              style: TextStyle(color: ds.dim, fontSize: PipText.body, letterSpacing: 2),
            ),
            Spacer(),
            Text(
              l10n.refreshIn(_refreshCountdown),
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.body,
                letterSpacing: 1,
              ),
            ),
            SizedBox(width: 14),
            Text(
              _totalFgMs > 0 ? _fmtDuration(_totalFgMs) : '0s',
              style: TextStyle(color: ds.primary, fontSize: PipText.title),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Period switch (segmented retro buttons) ----
  Widget _periodSwitch() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final p in Period.values) ...[
            Expanded(child: _periodBtn(p)),
            if (p != Period.all) SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _periodBtn(Period p) {
    final ds = context.ds;
    final active = _period == p;
    return GestureDetector(
      onTap: () {
        setState(() => _period = p);
        StatsDb.instance.setMeta('period', '${p.index}');
        _loadRows();
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? ds.primary : Colors.transparent,
          border: Border.all(color: ds.primary, width: 1),
        ),
        child: Text(
          _periodLabel(p).toUpperCase(),
          style: TextStyle(
            color: active ? ds.bg : ds.primary,
            fontSize: PipText.value,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  // ---- Access hint ----
  Widget _accessHint() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ds.hintBg,
        border: Border.all(color: ds.dark, width: 1),
      ),
      child: Column(
        children: [
          Text(
            l10n.usageAccessRequired,
            style: TextStyle(color: ds.primary, letterSpacing: 1),
          ),
          SizedBox(height: 6),
          Text(
            l10n.grantAccessHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: ds.dim, fontSize: PipText.heading),
          ),
          SizedBox(height: 10),
          _pipboyButton(l10n.grantAccess, _openUsageSettings),
        ],
      ),
    );
  }

  Widget _pipboyButton(String label, VoidCallback onTap) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: ds.primary,
          border: Border.all(color: ds.primary, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: ds.bg,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  // ---- Sort header ----
  /// The measured discharge the per-app figures are shares of.
  ///
  /// Shown so the estimates can be checked: they divide up this number and
  /// nothing else. Hidden until there is enough sample history, rather than
  /// rendering a zero that would read as a measurement.
  Widget _periodDrainLine() {
    if (_periodDrainUah <= 0) return const SizedBox.shrink();
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Text(
        l10n.periodDrainTotal((_periodDrainUah / 1000).toStringAsFixed(0)),
        style: TextStyle(color: ds.dim, fontSize: PipText.note),
      ),
    );
  }

  /// Filter box over the application list.
  ///
  /// Filters the already-loaded rows rather than re-querying: the percentages
  /// and the drain split are computed against the full period, and narrowing
  /// the query would silently rescale them to whatever was typed.
  Widget _searchField() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _appQuery = v),
        style: TextStyle(color: ds.primary, fontSize: PipText.value),
        cursorColor: ds.primary,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          hintText: l10n.searchHint,
          hintStyle: TextStyle(
            color: ds.dim,
            fontSize: PipText.label,
            letterSpacing: 1,
          ),
          prefixIcon: Icon(Icons.search, color: ds.dim, size: 22),
          suffixIcon: _appQuery.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: ds.dim, size: 22),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _appQuery = '');
                  },
                ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: ds.dark),
            borderRadius: BorderRadius.zero,
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: ds.primary),
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }

  Widget _sortHeader() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Text(
            l10n.applicationsHeader,
            style: TextStyle(color: ds.dim, fontSize: PipText.heading, letterSpacing: 1),
          ),
          Spacer(),
          _sortLabel(l10n.sortTime, SortKey.time),
          SizedBox(width: 14),
          _sortLabel(l10n.sortLaunch, SortKey.launches),
        ],
      ),
    );
  }

  Widget _sortLabel(String label, SortKey key) {
    final ds = context.ds;
    final isActive = _sortKey == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_sortKey == key) {
            _sortDesc = !_sortDesc;
          } else {
            _sortKey = key;
            _sortDesc = true;
          }
        });
        StatsDb.instance.setMeta('sort_key', '${_sortKey.index}');
        StatsDb.instance.setMeta('sort_desc', _sortDesc ? '1' : '0');
        _loadRows();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? ds.primary : ds.dim,
              fontSize: PipText.value,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 1,
            ),
          ),
          if (isActive)
            Icon(
              _sortDesc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
              size: 14,
              color: ds.primary,
            ),
        ],
      ),
    );
  }

  // ---- App list ----
  /// One application row.
  ///
  /// Split out of the old _appList ListView so the SYSTEM tab can render the
  /// whole page as one scroll view: pull-to-refresh only reacts to the
  /// scrollable under the finger, and with the metrics pinned above a short
  /// list there was nothing to pull on at the top of the screen.
  Widget _appRow(int i) {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    {
      {
        final r = _visibleRows[i];
        final pkg = r['package'] as String;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.dark, width: 1)),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            leading: FutureBuilder<String>(
              future: _iconFor(pkg),
              builder: (ctx, snap) {
                final b64 = snap.data;
                if (b64 != null && b64.isNotEmpty) {
                  return Image.memory(
                    base64Decode(b64),
                    width: 36,
                    height: 36,
                    gaplessPlayback: true,
                  );
                }
                return _PlaceholderIcon();
              },
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r['label'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ds.primary, fontSize: PipText.heading),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '> ${_fmtDuration(r['fg_ms'] as int)}',
                      style: TextStyle(color: ds.primary, fontSize: PipText.value),
                    ),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  pkg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ds.dim, fontSize: PipText.label),
                ),
                SizedBox(height: 3),
                _usageBar(r['fg_ms'] as int),
                SizedBox(height: 3),
                // One line, not a second bar. The amber bar drew
                // drain_pct/100 — the very same fraction the green usage bar
                // already draws — so the two were always identical in width
                // and carried one piece of information between them.
                if (_batteryInfoAvailable &&
                    (r['screen_pct'] as num?) != null &&
                    (r['screen_pct'] as num) > 0) ...[
                  Row(
                    children: [
                      Icon(
                        _charging ? Icons.flash_on : Icons.battery_std,
                        color: ds.battery,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _drainLabel(
                            l10n,
                            (r['screen_pct'] as num).toDouble(),
                            (r['drain_mah'] as num?)?.toDouble(),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ds.battery,
                            fontSize: PipText.body,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                '${r['launches']}x',
                style: TextStyle(color: ds.dim, fontSize: PipText.body),
              ),
            ),
            onTap: () => _showAppMenu(pkg),
            onLongPress: () => _resetPackage(pkg),
          ),
        );
      }
    }
  }

/// Proportional green usage bar for a row relative to total screen time.
  Widget _usageBar(int fgMs) {
    final ds = context.ds;
    final max = _totalFgMs > 0 ? _totalFgMs : 1;
    final frac = (fgMs / max).clamp(0.0, 1.0);
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: ds.dark,
        border: Border.all(color: ds.dark, width: 1),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: frac,
        child: Container(color: ds.primary),
      ),
    );
  }


  /// The line under a row: share of screen time, and the share of measured
  /// discharge attributed to it.
  ///
  /// The mAh figure carries a tilde and is absent entirely until real
  /// discharge has been measured, rather than showing a confident zero. On
  /// charger there is nothing to attribute, so it says that instead.
  String _drainLabel(AppLocalizations l10n, double screenPct, double? mah) {
    final share = l10n.appScreenShare(screenPct.toStringAsFixed(1));
    if (_charging) return '$share · ${l10n.appCharging}';
    if (mah == null || mah <= 0) {
      return '$share · ${l10n.appDrainMeasuring}';
    }
    return '$share · ${l10n.appDrainEstimate(mah.toStringAsFixed(0))}';
  }

  // ---- SysInfo tab (device technical details) ----
  Widget _sysInfoTab() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _deviceInfoFuture = StatsService.getDeviceInfo();
        });
        await _deviceInfoFuture;
      },
      color: ds.primary,
      backgroundColor: ds.bg,
      child: FutureBuilder<Map?>(
        future: _deviceInfoFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: ds.primary),
                  SizedBox(height: 16),
                  Text(l10n.scanning, style: TextStyle(color: ds.dim, fontSize: PipText.body)),
                ],
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Text(
                l10n.deviceInfoLoadFailed,
                style: TextStyle(color: ds.dangerBorder, fontSize: PipText.note, letterSpacing: 2),
              ),
            );
          }
          final data = snapshot.data!;
          // Enrich battery data with Dart-side capacity estimates
          final batteryMap = Map<String, dynamic>.from(data['battery'] as Map? ?? {});
          if (_calibratedCapacityUah > 0) batteryMap['calibratedCapacityUah'] = _calibratedCapacityUah;
          if (_realCapacityUah > 0) batteryMap['realCapacityUah'] = _realCapacityUah;
          if (_effectiveCapacityUah > 0) batteryMap['effectiveCapacityUah'] = _effectiveCapacityUah;
          String capacitySource = 'sysfs';
          if (_calibratedCapacityUah > 0) {
            capacitySource = 'calibrated';
          } else if (_designCapacityUah > 0) {
            capacitySource = 'design';
          } else if (_realCapacityUah > 0) {
            capacitySource = 'estimated';
          }
          batteryMap['capacitySource'] = capacitySource;
          data['battery'] = batteryMap;
          return ListView(
            padding: EdgeInsets.all(12),
            children: [
              _infoSection(ds, l10n, 'DEVICE', data['device'] as Map? ?? {}),
              SizedBox(height: 12),
              _infoSection(ds, l10n, 'SCREEN', data['screen'] as Map? ?? {}),
              SizedBox(height: 12),
              _infoSection(ds, l10n, 'BATTERY', data['battery'] as Map? ?? {}),
              SizedBox(height: 12),
              _infoSection(ds, l10n, 'STORAGE', data['storage'] as Map? ?? {}),
              SizedBox(height: 12),
              _infoSection(ds, l10n, 'MEMORY', data['memory'] as Map? ?? {}),
              SizedBox(height: 12),
              _infoSection(ds, l10n, 'CPU', data['cpu'] as Map? ?? {}),
              SizedBox(height: 12),
              _infoSection(ds, l10n, 'NETWORK', data['network'] as Map? ?? {}),
              SizedBox(height: 20),
              _privacySection(),
            ],
          );
        },
      ),
    );
  }

  // ---- INFO tab (Legal, About, Links) ----
  Widget _infoTab() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      color: ds.primary,
      backgroundColor: ds.bg,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(12),
      children: [
        _infoSection(ds, l10n, l10n.aboutApp, {
          'version': l10n.appVersion('1.1.0'),
          'description': l10n.appDescription,
        }),
        SizedBox(height: 12),
        _infoSection(ds, l10n, 'LEGAL', {
          'terms': l10n.termsOfService,
          'privacy': l10n.privacyPolicy,
        }, onTap: (key) {
          if (key == 'terms') _showTerms();
          if (key == 'privacy') _showPrivacy();
        }),
        SizedBox(height: 12),
        _infoSection(ds, l10n, 'LINKS', {
          'website': 'https://pipstats.pages.dev',
          'github': 'https://github.com/ShevchukIhor/PipStats',
          'terms_url': 'https://pipstats.pages.dev/terms',
          'privacy_url': 'https://pipstats.pages.dev/privacy',
        }),
      ],
      ),
    );
  }

  void _showTerms() {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.bg,
        title: Text(l10n.termsOfService, style: TextStyle(color: ds.primary, fontSize: PipText.heading)),
        content: SingleChildScrollView(
          child: Text(l10n.termsBody, style: TextStyle(color: ds.dim, fontSize: PipText.body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.close, style: TextStyle(color: ds.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _showTipModal() async {
    final l10n = AppLocalizations.of(context);
    if (_walletAddress == null) {
      _showSnack(l10n.tipNoWallet);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => TipWidget(walletAddress: _walletAddress!),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: context.ds.bg)),
        backgroundColor: context.ds.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- Info section helper (used by SYSINFO and INFO tabs) ----
  Widget _infoSection(DeviceStatsColors ds, AppLocalizations l10n, String title, Map map, {void Function(String)? onTap}) {
    if (map.isEmpty) return const SizedBox.shrink();
    final widgets = <Widget>[
      Text(
        '[ $title ]',
        style: TextStyle(
          color: ds.primary,
          fontSize: PipText.heading,
          letterSpacing: 2,
          shadows: ds.crt ? pipGlow(ds.primary) : null,
        ),
      ),
      SizedBox(height: 6),
    ];
    map.forEach((key, value) {
      final valStr = _formatValue(key, value);
      final rowWidget = Container(
        margin: EdgeInsets.only(bottom: 4),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: ds.panel,
          border: Border.all(color: ds.dark, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                _formatKey(key),
                style: TextStyle(color: ds.dim, fontSize: PipText.label, letterSpacing: 1),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(
                valStr,
                style: TextStyle(
                  color: ds.primary,
                  fontSize: PipText.value,
                  shadows: ds.crt ? pipGlow(ds.primary, blur: 5) : null,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
      if (onTap != null) {
        widgets.add(GestureDetector(
          onTap: () => onTap(key),
          child: rowWidget,
        ));
      } else {
        widgets.add(rowWidget);
      }
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  /// Turns a camelCase data key into a display label.
  ///
  /// Unit suffixes are stripped because [_formatValue] already renders the
  /// unit — leaving them produced labels that contradicted their own value,
  /// e.g. "MAX FREQ KHZ" next to "2.50 GHz". Keys that are not camelCase
  /// (network interface names like `wlan0 (IPv6)`) are passed through, since
  /// splitting on capitals mangled them into "WLAN0 ( I PV6)".
  String _formatKey(String key) {
    if (key.contains(' ') || key.contains('(')) return key.toUpperCase();

    var name = key;
    for (final suffix in const [
      'Bytes',
      'Khz',
      'Mah',
      'Uah',
      'Percent',
      'Dpi',
      'Hz',
      'Ma',
      'Ua',
      'Uv',
      'C',
      'V',
    ]) {
      if (name.length > suffix.length && name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length);
        break;
      }
    }
    return name
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
        .trim()
        .toUpperCase();
  }

  /// Renders a raw device-info value for display.
  ///
  /// Matching is on an explicit unit **suffix** in the key, not on fuzzy
  /// `contains`. The previous version matched `endsWith('v')` (so `voltageV`,
  /// already in volts, was reformatted as microvolts and rendered "4 µV") and
  /// `contains('temp') && contains('c')` (so `temperatureC`, already in °C,
  /// was divided by ten again and showed 27 °C as "2.7 °C").
  String _formatValue(String key, dynamic value) {
    if (value == null) return 'N/A';
    if (value is bool) return value ? 'YES' : 'NO';
    if (value is String) return value.isEmpty ? 'N/A' : value;

    final v = value is num ? value.toDouble() : double.tryParse('$value');
    if (v == null) return value.toString();

    if (key.endsWith('Bytes')) return _formatBytes(v);
    if (key.endsWith('Khz')) return _formatFreq(v);
    if (key.endsWith('Hz')) return '${v.round()} Hz';
    if (key.endsWith('C')) return '${v.toStringAsFixed(1)} °C';
    if (key.endsWith('V')) return '${v.toStringAsFixed(2)} V';
    if (key.endsWith('Mah')) return '${v.round()} mAh';
    if (key.endsWith('Ma')) return '${v.round()} mA';
    if (key.endsWith('Percent')) return '${v.round()}%';
    if (key.endsWith('Dpi')) return '${v.round()} dpi';

    // Legacy keys from readBatteryInfo, still carrying micro-units.
    if (key.endsWith('Uah')) return '${(v / 1000).round()} mAh';
    if (key.endsWith('Ua')) return '${(v / 1000).round()} mA';
    if (key.endsWith('Uv')) return '${(v / 1000000).toStringAsFixed(2)} V';

    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  String _formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.round()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatFreq(double khz) {
    if (khz >= 1000000) return '${(khz / 1000000).toStringAsFixed(2)} GHz';
    if (khz >= 1000) return '${(khz / 1000).toStringAsFixed(1)} MHz';
    return '${khz.round()} kHz';
  }





  Future<void> _showAppMenu(String pkg) async {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ds.bg,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ds.dark)),
              ),
              child: Text(
                '> $pkg',
                style: TextStyle(color: ds.dim, fontSize: PipText.heading),
              ),
            ),
            ListTile(
              leading: Icon(Icons.info_outline, color: ds.primary),
              title: Text(
                l10n.appInfo,
                style: TextStyle(color: ds.primary, letterSpacing: 1),
              ),
              onTap: () {
                Navigator.pop(ctx);
                StatsService.openAppInfo(pkg);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: ds.primary),
              title: Text(
                l10n.resetStats,
                style: TextStyle(color: ds.primary, letterSpacing: 1),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _resetPackage(pkg);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCalibrationDialog() async {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: '${(_effectiveCapacityUah / 1000.0).round()}');

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ds.bg,
          title: Text(l10n.calibrateCapacity, style: TextStyle(color: ds.primary, letterSpacing: 2)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.enterKnownCapacityMah, style: TextStyle(color: ds.dim, fontSize: PipText.label)),
              SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: TextStyle(color: ds.primary, fontSize: PipText.value),
                decoration: InputDecoration(
                  hintText: 'e.g. 4500',
                  hintStyle: TextStyle(color: ds.dark),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ds.dark)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: ds.primary)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel, style: TextStyle(color: ds.dim)),
            ),
            TextButton(
              onPressed: () {
                final mAh = int.tryParse(controller.text.trim());
                if (mAh != null && mAh > 0) {
                  _calibratedCapacityUah = mAh * 1000;
                  StatsDb.instance.setMeta('battery_calibrated_capacity_uah', '$_calibratedCapacityUah');
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
              child: Text(l10n.calibrate, style: TextStyle(color: ds.primary)),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _periodLabel(Period p) {
    final l10n = AppLocalizations.of(context);
    switch (p) {
      case Period.day:
        return l10n.periodDay;
      case Period.week:
        return l10n.periodWeek;
      case Period.month:
        return l10n.periodMonth;
      case Period.all:
        return l10n.periodAll;
    }
  }
}

/// Grey placeholder shown when an app icon is unavailable.
class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: ds.dark,
        border: Border.all(color: ds.dim, width: 1),
      ),
      child: Icon(Icons.android, color: ds.dim, size: 20),
    );
  }
}

/// CRT scanline overlay for Pip-Boy aesthetic.

