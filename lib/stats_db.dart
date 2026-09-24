import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Source-of-truth local store for device usage stats.
/// Android's UsageStatsManager only holds a few days of history, so we
/// poll deltas and accumulate them here permanently (survives reboot).
class StatsDb {
  StatsDb._();
  static final StatsDb instance = StatsDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'device_stats.db');
    final database = await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE app_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            package TEXT NOT NULL,
            event_type INTEGER NOT NULL, -- 1 = foreground, 0 = background
            ts INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_events_dedup '
          'ON app_events(package, event_type, ts)',
        );
        await db.execute(
          'CREATE INDEX idx_events_pkg_ts ON app_events(package, ts)',
        );
        await db.execute('CREATE INDEX idx_events_ts ON app_events(ts)');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE daily_stats (
            package TEXT NOT NULL,
            day INTEGER NOT NULL,
            fg_ms INTEGER NOT NULL,
            PRIMARY KEY (package, day)
          )
        ''');
        await db.execute('''
          CREATE TABLE battery_samples (
            ts INTEGER PRIMARY KEY,
            counter_uah INTEGER NOT NULL,
            current_ua INTEGER NOT NULL,
            charging INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE vault_token_accounts (
            wallet_address TEXT NOT NULL,
            pubkey TEXT NOT NULL,
            mint TEXT NOT NULL,
            owner TEXT NOT NULL,
            amount INTEGER NOT NULL,
            delegate TEXT,
            state INTEGER NOT NULL,
            delegated_amount INTEGER NOT NULL,
            close_authority TEXT,
            is_native INTEGER NOT NULL,
            native_amount INTEGER NOT NULL,
            PRIMARY KEY (wallet_address, pubkey)
          )
        ''');
        await db.execute('''
          CREATE TABLE vault_assets (
            wallet_address TEXT NOT NULL,
            id TEXT NOT NULL,
            interface TEXT NOT NULL,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            balance TEXT NOT NULL,
            decimals INTEGER NOT NULL,
            burnt INTEGER NOT NULL,
            compressed INTEGER NOT NULL,
            PRIMARY KEY (wallet_address, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE vault_txs (
            wallet_address TEXT NOT NULL,
            signature TEXT NOT NULL,
            slot INTEGER NOT NULL,
            err TEXT,
            block_time INTEGER NOT NULL,
            memo TEXT,
            PRIMARY KEY (wallet_address, signature)
          )
        ''');
        await db.execute('''
          CREATE TABLE vault_tx_details (
            wallet_address TEXT NOT NULL,
            signature TEXT NOT NULL,
            fee_lamports INTEGER NOT NULL,
            programs TEXT NOT NULL,
            transfers TEXT NOT NULL,
            sol_transfers TEXT NOT NULL,
            PRIMARY KEY (wallet_address, signature)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _upgradeTo2(db);
        }
        if (oldVersion < 3) {
          await _upgradeTo3(db);
        }
        if (oldVersion < 4) {
          await _upgradeTo4(db);
        }
        if (oldVersion < 5) {
          await _upgradeTo5(db);
        }
      },
    );
    return database;
  }

  /// v1 -> v2: remove duplicate rows, then add the dedup unique index.
  Future<void> _upgradeTo2(Database db) async {
    await db.execute(
      'DELETE FROM app_events WHERE id NOT IN '
      '(SELECT MIN(id) FROM app_events GROUP BY package, event_type, ts)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_events_dedup '
      'ON app_events(package, event_type, ts)',
    );
  }

  /// v2 -> v3: add the daily snapshot table (longer retention source).
  Future<void> _upgradeTo3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_stats (
        package TEXT NOT NULL,
        day INTEGER NOT NULL,
        fg_ms INTEGER NOT NULL,
        PRIMARY KEY (package, day)
      )
    ''');
  }

  /// v3 -> v4: add the battery sample table (power-drain estimation).
  Future<void> _upgradeTo4(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS battery_samples (
        ts INTEGER PRIMARY KEY,
        counter_uah INTEGER NOT NULL,
        current_ua INTEGER NOT NULL,
        charging INTEGER NOT NULL
      )
    ''');
  }

  /// v4 -> v5: add vault data tables (token accounts, assets, transactions).
  Future<void> _upgradeTo5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_token_accounts (
        wallet_address TEXT NOT NULL,
        pubkey TEXT NOT NULL,
        mint TEXT NOT NULL,
        owner TEXT NOT NULL,
        amount INTEGER NOT NULL,
        delegate TEXT,
        state INTEGER NOT NULL,
        delegated_amount INTEGER NOT NULL,
        close_authority TEXT,
        is_native INTEGER NOT NULL,
        native_amount INTEGER NOT NULL,
        PRIMARY KEY (wallet_address, pubkey)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_assets (
        wallet_address TEXT NOT NULL,
        id TEXT NOT NULL,
        interface TEXT NOT NULL,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        balance TEXT NOT NULL,
        decimals INTEGER NOT NULL,
        burnt INTEGER NOT NULL,
        compressed INTEGER NOT NULL,
        PRIMARY KEY (wallet_address, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_txs (
        wallet_address TEXT NOT NULL,
        signature TEXT NOT NULL,
        slot INTEGER NOT NULL,
        err TEXT,
        block_time INTEGER NOT NULL,
        memo TEXT,
        PRIMARY KEY (wallet_address, signature)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_tx_details (
        wallet_address TEXT NOT NULL,
        signature TEXT NOT NULL,
        fee_lamports INTEGER NOT NULL,
        programs TEXT NOT NULL,
        transfers TEXT NOT NULL,
        sol_transfers TEXT NOT NULL,
        PRIMARY KEY (wallet_address, signature)
      )
    ''');
  }

  /// Mark of last polled event timestamp (epoch ms). Returns 0 if never.
  Future<int> getLastSyncTs() async {
    final d = await db;
    final rows = await d.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['last_sync_ts'],
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> setLastSyncTs(int ts) async {
    final d = await db;
    await d.insert('meta', {
      'key': 'last_sync_ts',
      'value': '$ts',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Insert a battery sample (deduplicated by timestamp).
  Future<void> insertBatterySample(
    int ts,
    int counterUah,
    int currentUa,
    bool charging,
  ) async {
    final d = await db;
    await d.insert('battery_samples', {
      'ts': ts,
      'counter_uah': counterUah,
      'current_ua': currentUa,
      'charging': charging ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// All battery samples in [from, to], oldest first.
  ///
  /// Needed to measure real discharge across a period: the first and last
  /// samples alone cannot tell discharge from a charge that happened in
  /// between, because the counter rises while charging.
  Future<List<Map<String, Object?>>> batterySamplesBetween(
    int from,
    int to,
  ) async {
    final d = await db;
    return d.query(
      'battery_samples',
      where: 'ts >= ? AND ts <= ?',
      whereArgs: [from, to],
      orderBy: 'ts ASC',
    );
  }

  /// Earliest battery sample timestamp at or after [ts], or null.
  Future<Map<String, Object?>?> firstBatterySampleAtOrAfter(
    int ts,
  ) async {
    final d = await db;
    final rows = await d.query(
      'battery_samples',
      where: 'ts >= ?',
      whereArgs: [ts],
      orderBy: 'ts ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Latest battery sample at or before [ts], or null.
  Future<Map<String, Object?>?> lastBatterySampleAtOrBefore(int ts) async {
    final d = await db;
    final rows = await d.query(
      'battery_samples',
      where: 'ts <= ?',
      whereArgs: [ts],
      orderBy: 'ts DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Vault data persistence methods.

  /// Save token accounts for a wallet address.
  Future<void> saveVaultTokenAccounts(
    String walletAddress,
    List<Map<String, Object?>> accounts,
  ) async {
    final d = await db;
    final batch = d.batch();
    for (final a in accounts) {
      batch.insert('vault_token_accounts', {
        'wallet_address': walletAddress,
        'pubkey': a['pubkey'],
        'mint': a['mint'],
        'owner': a['owner'],
        'amount': a['amount'],
        'delegate': a['delegate'],
        'state': a['state'],
        'delegated_amount': a['delegatedAmount'],
        'close_authority': a['closeAuthority'],
        'is_native': a['isNative'] == true ? 1 : 0,
        'native_amount': a['nativeAmount'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Load token accounts for a wallet address.
  Future<List<Map<String, Object?>>> loadVaultTokenAccounts(
    String walletAddress,
  ) async {
    final d = await db;
    return await d.query(
      'vault_token_accounts',
      where: 'wallet_address = ?',
      whereArgs: [walletAddress],
    );
  }

  /// Save assets for a wallet address.
  Future<void> saveVaultAssets(
    String walletAddress,
    List<Map<String, Object?>> assets,
  ) async {
    final d = await db;
    final batch = d.batch();
    for (final a in assets) {
      batch.insert('vault_assets', {
        'wallet_address': walletAddress,
        'id': a['id'],
        'interface': a['interface'],
        'name': a['name'],
        'symbol': a['symbol'],
        'balance': a['balance'],
        'decimals': a['decimals'],
        'burnt': a['burnt'] == true ? 1 : 0,
        'compressed': a['compressed'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Load assets for a wallet address.
  Future<List<Map<String, Object?>>> loadVaultAssets(
    String walletAddress,
  ) async {
    final d = await db;
    return await d.query(
      'vault_assets',
      where: 'wallet_address = ?',
      whereArgs: [walletAddress],
    );
  }

  /// Save transactions for a wallet address.
  Future<void> saveVaultTxs(
    String walletAddress,
    List<Map<String, Object?>> txs,
    Map<String, Map<String, Object?>> txDetails,
  ) async {
    final d = await db;
    final batch = d.batch();
    for (final t in txs) {
      batch.insert('vault_txs', {
        'wallet_address': walletAddress,
        'signature': t['signature'],
        'slot': t['slot'],
        'err': t['err']?.toString(),
        'block_time': t['blockTime'],
        'memo': t['memo'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final entry in txDetails.entries) {
      final td = entry.value;
      batch.insert('vault_tx_details', {
        'wallet_address': walletAddress,
        'signature': entry.key,
        'fee_lamports': td['feeLamports'],
        'programs': (td['programs'] as List?)?.join(',') ?? '',
        'transfers': (td['transfers'] as List?)?.map((t) => '${t['mint']}|${t['amount']}|${t['destination']}|${t['source']}').join(';') ?? '',
        'sol_transfers': (td['solTransfers'] as List?)?.map((t) => '${t['destination']}|${t['source']}|${t['lamports']}').join(';') ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Load transactions for a wallet address.
  Future<List<Map<String, Object?>>> loadVaultTxs(
    String walletAddress,
  ) async {
    final d = await db;
    final txs = await d.query(
      'vault_txs',
      where: 'wallet_address = ?',
      whereArgs: [walletAddress],
      orderBy: 'block_time DESC',
    );
    final details = await d.query(
      'vault_tx_details',
      where: 'wallet_address = ?',
      whereArgs: [walletAddress],
    );
    final detailMap = {for (var d in details) d['signature'] as String: d};
    for (var t in txs) {
      final sig = t['signature'] as String;
      if (detailMap.containsKey(sig)) {
        final td = detailMap[sig]!;
        t['feeLamports'] = td['fee_lamports'];
        t['programs'] = (td['programs'] as String).split(',');
        t['transfers'] = (td['transfers'] as String).split(';').map((t) {
          final parts = t.split('|');
          return {
            'mint': parts[0],
            'amount': parts[1],
            'destination': parts[2],
            'source': parts[3],
          };
        }).toList();
        t['solTransfers'] = (td['sol_transfers'] as String).split(';').map((t) {
          final parts = t.split('|');
          return {
            'destination': parts[0],
            'source': parts[1],
            'lamports': int.parse(parts[2]),
          };
        }).toList();
      }
    }
    return txs;
  }

  /// Delete all vault data for a wallet address.
  Future<void> deleteVaultData(String walletAddress) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('vault_token_accounts', where: 'wallet_address = ?', whereArgs: [walletAddress]);
    batch.delete('vault_assets', where: 'wallet_address = ?', whereArgs: [walletAddress]);
    batch.delete('vault_txs', where: 'wallet_address = ?', whereArgs: [walletAddress]);
    batch.delete('vault_tx_details', where: 'wallet_address = ?', whereArgs: [walletAddress]);
    await batch.commit(noResult: true);
  }

  /// Generic key/value store for app preferences (period, sort, tab, theme).
  Future<void> setMeta(String key, String value) async {
    final d = await db;
    await d.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Read a preference string, or null when absent.
  Future<String?> getMeta(String key) async {
    final d = await db;
    final rows = await d.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Insert raw events (foreground/background), dedup by timestamp+package+type.
  Future<void> insertEvents(List<Map<String, Object?>> events) async {
    if (events.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final e in events) {
      batch.insert('app_events', {
        'package': e['package'],
        'event_type': e['event_type'],
        'ts': e['ts'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// Query aggregated usage for a period.
  /// Returns rows: {package, fg_ms, launches}.
  Future<List<Map<String, Object?>>> usageSince(int periodStartMs) async {
    return await _computeUsage(periodStartMs);
  }

  Future<List<Map<String, Object?>>> _computeUsage(int periodStartMs) async {
    final d = await db;
    final events = await d.query(
      'app_events',
      where: 'ts >= ?',
      whereArgs: [periodStartMs],
      orderBy: 'ts ASC',
    );
    final openSessions = await _openSessionsAt(d, periodStartMs);
    // Count a still-open session up to now, not merely up to the last stored
    // event: with no new events for an hour that hour was silently dropped.
    final base = aggregateUsage(
      events,
      openSessions: openSessions,
      windowStart: periodStartMs,
      observationEnd: DateTime.now().millisecondsSinceEpoch,
    );

    // Events only cover from the earliest stored event onward. For any part of
    // the period that predates that, fill in from the daily snapshots table
    // (longer retention) so WEEK/MONTH/ALL still span multi-day history.
    final earliest = await earliestEventTs();
    if (earliest == null || earliest <= periodStartMs) return base;

    final daily = await dailyUsageBetween(periodStartMs, earliest);
    if (daily.isEmpty) return base;

    final merged = <String, int>{};
    for (final r in base) {
      merged[r['package'] as String] = (r['fg_ms'] as int?) ?? 0;
    }
    for (final r in daily) {
      final pkg = r['package'] as String;
      merged[pkg] = (merged[pkg] ?? 0) + ((r['fg_ms'] as int?) ?? 0);
    }
    final out = base.where((r) => merged.containsKey(r['package'])).toList();
    final known = out.map((r) => r['package'] as String).toSet();
    for (final e in merged.entries) {
      if (!known.contains(e.key)) {
        out.add({
          'package': e.key,
          'fg_ms': e.value,
          'launches': 0,
        });
      } else {
        final i = out.indexWhere((r) => r['package'] == e.key);
        out[i]['fg_ms'] = e.value;
      }
    }
    out.sort((a, b) => (b['fg_ms'] as int).compareTo(a['fg_ms'] as int));
    return out;
  }

  /// Packages whose most recent event before [ts] is a foreground: the session
  /// is still open at [ts]. Returns package -> last foreground ts.
  ///
  /// Uses the max row id per package (id is monotonic with ts) so only the
  /// latest pre-window event of each package is loaded, not the whole history.
  Future<Map<String, int>> _openSessionsAt(Database d, int ts) async {
    // Pick each package's latest pre-window event by **timestamp**, using id
    // only to break ties. Ordering by MAX(id) was wrong: StatsService.sync
    // re-reads a 5-minute overlap window, so a late-delivered event can be
    // inserted with a higher id but an older ts and would win incorrectly,
    // flipping a session's open/closed state at the window boundary.
    final rows = await d.rawQuery(
      'SELECT e.package, e.event_type, e.ts FROM app_events e '
      'JOIN (SELECT package, MAX(ts) AS mts FROM app_events '
      '      WHERE ts < ? GROUP BY package) m '
      '  ON e.package = m.package AND e.ts = m.mts '
      'WHERE e.ts < ? '
      'GROUP BY e.package HAVING e.id = MAX(e.id)',
      [ts, ts],
    );
    final open = <String, int>{};
    for (final e in rows) {
      if (e['event_type'] == 1) open[e['package'] as String] = e['ts'] as int;
    }
    return open;
  }

  /// Reset stats for a single package (delete its events).
  Future<void> resetPackage(String package) async {
    final d = await db;
    await d.delete('app_events', where: 'package = ?', whereArgs: [package]);
  }

  /// Reset stats for a group of packages.
  Future<void> resetPackages(List<String> packages) async {
    if (packages.isEmpty) return;
    final d = await db;
    final placeholders = List.filled(packages.length, '?').join(',');
    await d.delete(
      'app_events',
      where: 'package IN ($placeholders)',
      whereArgs: packages,
    );
  }

  /// List all known packages (for reset group dialog).
  Future<List<String>> allPackages() async {
    final d = await db;
    final rows = await d.rawQuery('SELECT DISTINCT package FROM app_events');
    return rows.map((r) => r['package'] as String).toList();
  }

  /// Timestamp (epoch ms) of the oldest stored event, or null when empty.
  /// Used to detect when a selected period predates the accumulated history.
  Future<int?> earliestEventTs() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT MIN(ts) AS m FROM app_events',
    );
    if (rows.isEmpty || rows.first['m'] == null) return null;
    return (rows.first['m'] as num).toInt();
  }

  /// Upsert per-package-per-day foreground totals (daily snapshot).
  Future<void> upsertDailyStats(List<Map<String, Object?>> days) async {
    if (days.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final row in days) {
      batch.insert('daily_stats', {
        'package': row['package'],
        'day': row['day'],
        'fg_ms': row['fg_ms'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Foreground ms per package from daily snapshots whose [day] falls in
  /// `[fromMs, toMs)`. Sums across the covered days.
  Future<List<Map<String, Object?>>> dailyUsageBetween(
    int fromMs,
    int toMs,
  ) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT package, SUM(fg_ms) AS total FROM daily_stats '
      'WHERE day >= ? AND day < ? GROUP BY package',
      [fromMs, toMs],
    );
    return rows.map((r) {
      return <String, Object?>{
        'package': r['package'],
        'fg_ms': (r['total'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }
}

/// Aggregates raw usage events into per-package {package, fg_ms, launches}.
///
/// Events must be ordered by `ts` ascending. Pairs each foreground (type 1)
/// with the following background (type 0); a still-open session is counted as
/// a launch but contributes no foreground time until it is closed.
///
/// A foreground that arrives while the previous session is still open
/// (fg -> fg without a background) closes the previous segment at its own ts
/// so no time is lost, and is deduped: it does not count as a new launch.
///
/// [openSessions] seeds sessions already open when the window began (package ->
/// last foreground ts before the window). [windowStart] clamps their counted
/// time so only the in-window portion is attributed.
List<Map<String, Object?>> aggregateUsage(
  List<Map<String, Object?>> events, {
  Map<String, int>? openSessions,
  int? windowStart,
  int? observationEnd,
}) {
  final Map<String, int> fgMs = {};
  final Map<String, int> launches = {};
  final Map<String, int> openSince = {
    ...?openSessions, // sessions already open when the window began
  };

  int clamp(int start) =>
      (windowStart != null && start < windowStart) ? windowStart : start;

  for (final e in events) {
    final pkg = e['package'] as String;
    final type = e['event_type'] as int;
    final ts = e['ts'] as int;

    if (type == 1) {
      final prev = openSince[pkg];
      if (prev != null) {
        if (ts > prev) {
          // fg -> fg without a background: close the previous segment at this
          // foreground's ts so no time is lost; the session is deduped.
          fgMs[pkg] = (fgMs[pkg] ?? 0) + (ts - clamp(prev));
          openSince[pkg] = ts;
        }
        // Same-ts duplicate foreground: ignore entirely.
        continue;
      }
      launches[pkg] = (launches[pkg] ?? 0) + 1;
      openSince[pkg] = ts;
    } else if (type == 0) {
      final start = openSince.remove(pkg);
      if (start != null && ts > start) {
        fgMs[pkg] = (fgMs[pkg] ?? 0) + (ts - clamp(start));
      }
    }
  }

  // Count remaining ongoing sessions up to the end of observations.
  final end = observationEnd ?? (events.isEmpty ? 0 : events.last['ts'] as int);
  for (final entry in openSince.entries) {
    final pkg = entry.key;
    final start = entry.value;
    if (end > clamp(start)) {
      fgMs[pkg] = (fgMs[pkg] ?? 0) + (end - clamp(start));
    }
  }

  final result = <Map<String, Object?>>[];
  final allPkgs = <String>{...fgMs.keys, ...launches.keys};
  for (final pkg in allPkgs) {
    result.add({
      'package': pkg,
      'fg_ms': fgMs[pkg] ?? 0,
      'launches': launches[pkg] ?? 0,
    });
  }
  result.sort((a, b) => (b['fg_ms'] as int).compareTo(a['fg_ms'] as int));
  return result;
}
