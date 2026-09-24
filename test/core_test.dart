import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/base58.dart' as sol_base58;

import 'package:pipstats/base58.dart';
import 'package:pipstats/domains.dart';
import 'package:pipstats/rpc_config.dart';
import 'package:pipstats/solscan_service.dart';
import 'package:pipstats/stats_db.dart';
import 'package:pipstats/revoke.dart';
import 'package:pipstats/main.dart';
import 'package:pipstats/wallet_auth.dart';

void main() {
  group('base58Encode', () {
    test('matches the reference implementation', () {
      final inputs = <List<int>>[
        <int>[],
        <int>[0],
        <int>[0, 0, 0],
        <int>[0, 1],
        <int>[0, 0, 255],
        List<int>.filled(32, 0),
        List<int>.filled(64, 0),
        <int>[1, 2, 3, 4, 5, 6, 7, 8],
        <int>[255, 254, 253, 252, 251, 250, 0, 0, 0],
      ];
      for (final bytes in inputs) {
        expect(
          base58Encode(Uint8List.fromList(bytes)),
          sol_base58.base58encode(bytes),
          reason: 'mismatch for $bytes',
        );
      }
    });

    test('leading zero bytes become one char each', () {
      expect(base58Encode(Uint8List(0).sublist(0)), '');
      expect(base58Encode(Uint8List.fromList([0])), '1');
      expect(base58Encode(Uint8List.fromList([0, 0, 0])), '111');
      expect(base58Encode(Uint8List(32)), '1' * 32);
    });
  });

  group('parseTokenAccount', () {
    // Fixtures follow the real `spl_token::state::Account` Pack layout:
    // fixed 165 bytes, 4-byte little-endian COption tags, and `is_native`
    // positioned between `state` and `delegated_amount`.
    void u32le(Uint8List b, int o, int v) {
      for (var i = 0; i < 4; i++) {
        b[o + i] = (v >> (8 * i)) & 0xff;
      }
    }

    void u64le(Uint8List b, int o, int v) {
      for (var i = 0; i < 8; i++) {
        b[o + i] = (v >> (8 * i)) & 0xff;
      }
    }

    final mintBytes = List<int>.filled(32, 7);
    final ownerBytes = List<int>.filled(32, 9);
    final delegateBytes = List<int>.generate(32, (i) => (i * 5 + 3) & 0xff);
    final closeBytes = List<int>.generate(32, (i) => (i * 11 + 1) & 0xff);

    Uint8List build({
      int amount = 0,
      List<int>? delegate,
      int state = 1,
      int? nativeAmount, // null => is_native is None
      int delegatedAmount = 0,
      List<int>? closeAuthority,
      int extensionBytes = 0, // Token-2022 appends after the base
    }) {
      final b = Uint8List(165 + extensionBytes);
      b.setRange(0, 32, mintBytes);
      b.setRange(32, 64, ownerBytes);
      u64le(b, 64, amount);
      if (delegate != null) {
        u32le(b, 72, 1);
        b.setRange(76, 108, delegate);
      }
      b[108] = state;
      if (nativeAmount != null) {
        u32le(b, 109, 1);
        u64le(b, 113, nativeAmount);
      }
      u64le(b, 121, delegatedAmount);
      if (closeAuthority != null) {
        u32le(b, 129, 1);
        b.setRange(133, 165, closeAuthority);
      }
      return b;
    }

    test('returns null when shorter than the 165-byte base layout', () {
      expect(parseTokenAccount(Uint8List(164)), isNull);
      expect(parseTokenAccount(Uint8List(92)), isNull);
      expect(parseTokenAccount(Uint8List(0)), isNull);
    });

    test('decodes a plain initialized account', () {
      final d = build(amount: 123456, state: 1);
      expect(d.length, 165);
      final info = parseTokenAccount(d)!;
      expect(info.mint, base58Encode(Uint8List.fromList(mintBytes)));
      expect(info.owner, base58Encode(Uint8List.fromList(ownerBytes)));
      expect(info.amount, 123456);
      expect(info.delegate, isNull);
      expect(info.hasDelegate, isFalse);
      // The old 1-byte-tag reader returned 0 here for every real account,
      // breaking frozen/initialized detection.
      expect(info.state, 1);
      expect(info.delegatedAmount, 0);
      expect(info.closeAuthority, isNull);
      expect(info.isNative, isFalse);
      expect(info.nativeAmount, 0);
    });

    test('reads the delegate at offset 76, not shifted by the tag', () {
      final d = build(amount: 42, delegate: delegateBytes, delegatedAmount: 7);
      final info = parseTokenAccount(d)!;
      expect(info.hasDelegate, isTrue);
      // The exact address matters: a 3-byte shift still yields a plausible
      // looking base58 string while naming the wrong spender.
      expect(info.delegate, base58Encode(Uint8List.fromList(delegateBytes)));
      expect(info.delegatedAmount, 7);
      expect(info.state, 1);
    });

    test('decodes a close authority', () {
      final d = build(amount: 1, closeAuthority: closeBytes);
      final info = parseTokenAccount(d)!;
      expect(info.hasCloseAuthority, isTrue);
      expect(info.closeAuthority, base58Encode(Uint8List.fromList(closeBytes)));
    });

    test('a close authority is still found when a delegate is present', () {
      final d = build(
        amount: 1,
        delegate: delegateBytes,
        delegatedAmount: 2,
        closeAuthority: closeBytes,
      );
      final info = parseTokenAccount(d)!;
      expect(info.delegate, base58Encode(Uint8List.fromList(delegateBytes)));
      expect(info.delegatedAmount, 2);
      expect(info.closeAuthority, base58Encode(Uint8List.fromList(closeBytes)));
    });

    test('wrapped SOL: is_native carries the rent-exempt reserve', () {
      final d = build(amount: 5, nativeAmount: 2039280, delegatedAmount: 11);
      final info = parseTokenAccount(d)!;
      expect(info.isNative, isTrue);
      expect(info.nativeAmount, 2039280);
      // is_native sits *before* delegated_amount; reading them in the wrong
      // order corrupts both.
      expect(info.delegatedAmount, 11);
    });

    test('a frozen account reports state 2', () {
      expect(parseTokenAccount(build(state: 2))!.state, 2);
    });

    test('a u64 amount above 2^63 saturates instead of going negative', () {
      final d = build();
      // amount = 0xFFFFFFFFFFFFFFFF
      for (var i = 0; i < 8; i++) {
        d[64 + i] = 0xff;
      }
      final info = parseTokenAccount(d)!;
      expect(info.amount, isNonNegative);
      expect(info.amount, 0x7FFFFFFFFFFFFFFF);
    });

    test('Token-2022 extensions after the base are ignored', () {
      final d = build(amount: 99, delegate: delegateBytes, extensionBytes: 83);
      expect(d.length, greaterThan(165));
      final info = parseTokenAccount(d)!;
      expect(info.amount, 99);
      expect(info.delegate, base58Encode(Uint8List.fromList(delegateBytes)));
    });
  });

  group('formatBytes', () {
    test('uses SI units, matching carriers and Android settings', () {
      // 1000, not 1024: a user comparing this against their data plan or the
      // system settings screen would otherwise see a different number.
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1000), '1.0 kB');
      expect(formatBytes(1500000), '1.5 MB');
      expect(formatBytes(2000000000), '2.0 GB');
    });

    test('drops the decimal once it stops carrying information', () {
      expect(formatBytes(150000000), '150 MB');
    });

    test('handles zero', () {
      expect(formatBytes(0), '0 B');
    });
  });

  group('filterRows', () {
    final rows = <Map<String, Object?>>[
      {'package': 'com.pipstats.app', 'label': 'PipStats'},
      {'package': 'ag.jup.jupiter.android', 'label': 'Jupiter'},
      {'package': 'com.android.settings', 'label': 'Settings'},
    ];

    test('an empty query returns the list untouched', () {
      expect(filterRows(rows, ''), same(rows));
      expect(filterRows(rows, '   '), same(rows));
    });

    test('matches the label, ignoring case', () {
      expect(filterRows(rows, 'jUpI').single['label'], 'Jupiter');
    });

    test('matches the package too', () {
      // Clones and work-profile copies share a display name; the package id is
      // the only thing that tells them apart.
      expect(filterRows(rows, 'ag.jup').single['label'], 'Jupiter');
      expect(filterRows(rows, 'com.').length, 2);
    });

    test('no match yields an empty list, not everything', () {
      expect(filterRows(rows, 'zzz'), isEmpty);
    });
  });

  group('CSV export', () {
    test('quotes fields that would break the row', () {
      // App labels routinely contain commas; an unescaped one silently shifts
      // every later column, which is worse than a visibly broken file.
      expect(csvField('Maps, Navigate & Explore'), '"Maps, Navigate & Explore"');
      expect(csvField('say "hi"'), '"say ""hi"""');
      expect(csvField('two\nlines'), '"two\nlines"');
    });

    test('leaves ordinary fields alone', () {
      expect(csvField('com.pipstats.app'), 'com.pipstats.app');
      expect(csvField(1234), '1234');
      expect(csvField(null), '');
    });

    test('builds a header and one row per entry', () {
      final out = buildCsv(
        ['package', 'label'],
        [
          ['a', 'App A'],
          ['b', 'B, Inc'],
        ],
      );
      final lines = out.trim().split('\n');
      expect(lines, hasLength(3));
      expect(lines.first, 'package,label');
      expect(lines.last, 'b,"B, Inc"');
    });
  });

  group('drainBetween', () {
    Map<String, Object?> s(int ts, int counter, {bool charging = false}) => {
      'ts': ts,
      'counter_uah': counter,
      'charging': charging ? 1 : 0,
    };

    test('sums the drops between consecutive samples', () {
      expect(
        drainBetween([s(1, 3000000), s(2, 2900000), s(3, 2750000)]),
        250000,
      );
    });

    test('a charge in the middle does not cancel earlier drain', () {
      // First-minus-last would report 0 here and hide 200000 µAh of real use.
      final out = drainBetween([
        s(1, 3000000),
        s(2, 2800000),
        s(3, 3000000),
      ]);
      expect(out, 200000);
    });

    test('ignores pairs recorded on charger', () {
      expect(
        drainBetween([
          s(1, 3000000, charging: true),
          s(2, 2500000, charging: true),
          s(3, 2400000),
        ]),
        isNot(500000),
        reason: 'a counter falling while plugged in is not app consumption',
      );
    });

    test('says it does not know rather than reporting zero', () {
      expect(drainBetween([]), -1);
      expect(drainBetween([s(1, 3000000)]), -1, reason: 'one sample');
      expect(
        drainBetween([s(1, 3000000, charging: true), s(2, 2900000, charging: true)]),
        -1,
        reason: 'every pair was on charger, so nothing was measured',
      );
    });

    test('a flat counter is a real zero, not unknown', () {
      expect(drainBetween([s(1, 3000000), s(2, 3000000)]), 0);
    });

    test('skips samples with no counter reading', () {
      expect(drainBetween([s(1, 0), s(2, 0)]), -1);
    });
  });

  group('chargeAtLevel', () {
    // 4500 mAh design capacity, as read from power_profile.xml on the Seeker.
    const cap = 4500000;

    test('scales the trusted capacity by the level', () {
      expect(chargeAtLevel(cap, 100, 100), 4500000);
      expect(chargeAtLevel(cap, 67, 100), 3015000);
      expect(chargeAtLevel(cap, 43, 100), 1935000);
      expect(chargeAtLevel(cap, 0, 100), 0);
    });

    test('honours a scale other than 100', () {
      // level is a fraction of scale, not a percentage: 50 of 200 is a quarter.
      expect(chargeAtLevel(cap, 50, 200), 1125000);
      expect(chargeAtLevel(cap, 100, 200), 2250000);
      expect(chargeAtLevel(cap, 200, 200), 4500000);
    });

    test('never exceeds the capacity', () {
      // A level above scale is nonsense but has been seen from OEM drivers;
      // reporting more charge than the battery holds is worse than clamping.
      expect(chargeAtLevel(cap, 150, 100), cap);
    });

    test('refuses rather than inventing a number', () {
      expect(chargeAtLevel(-1, 50, 100), -1, reason: 'no capacity to scale');
      expect(chargeAtLevel(cap, 50, 0), -1, reason: 'scale of zero');
      expect(chargeAtLevel(cap, -1, 100), -1, reason: 'level unknown');
    });

    test('is exact at the levels the UI renders', () {
      // The strip divides by 1000 and rounds; these must not drift by an mAh.
      expect((chargeAtLevel(cap, 43, 100) / 1000).round(), 1935);
      expect((chargeAtLevel(cap, 12, 100) / 1000).round(), 540);
    });
  });

  group('aggregateUsage', () {
    Map<String, Object?> ev(String pkg, int type, int ts) => {
      'package': pkg,
      'event_type': type,
      'ts': ts,
    };

    test('pairs foreground/background into fg_ms and counts launches', () {
      final rows = aggregateUsage([
        ev('a', 1, 100),
        ev('a', 0, 200),
        ev('b', 1, 150),
        ev('b', 0, 250),
      ]);
      final byPkg = {for (final r in rows) r['package']: r};
      expect(byPkg['a']!['fg_ms'], 100);
      expect(byPkg['a']!['launches'], 1);
      expect(byPkg['b']!['fg_ms'], 100);
      expect(byPkg['b']!['launches'], 1);
    });

    test('open session counts a launch but no time', () {
      final rows = aggregateUsage([
        ev('a', 1, 100),
        ev('a', 0, 200),
        ev('a', 1, 500),
      ]);
      final a = rows.firstWhere((r) => r['package'] == 'a');
      expect(a['fg_ms'], 100);
      expect(a['launches'], 2);
    });

    test('background without foreground is ignored', () {
      final rows = aggregateUsage([ev('a', 0, 200)]);
      expect(rows, isEmpty);
    });

    test('sorts by fg_ms descending', () {
      final rows = aggregateUsage([
        ev('a', 1, 100),
        ev('a', 0, 110),
        ev('b', 1, 100),
        ev('b', 0, 300),
      ]);
      expect(rows[0]['package'], 'b');
      expect(rows[1]['package'], 'a');
    });

    test('fg -> fg without background closes segment and dedups launch', () {
      final rows = aggregateUsage([
        ev('a', 1, 100),
        ev('a', 1, 300),
        ev('a', 0, 400),
      ]);
      final a = rows.firstWhere((r) => r['package'] == 'a');
      expect(a['fg_ms'], 300);
      expect(a['launches'], 1);
    });

    test('same-ts duplicate foreground is ignored', () {
      final rows = aggregateUsage([
        ev('a', 1, 100),
        ev('a', 1, 100),
        ev('a', 0, 200),
      ]);
      final a = rows.firstWhere((r) => r['package'] == 'a');
      expect(a['fg_ms'], 100);
      expect(a['launches'], 1);
    });

    test('open session across boundary counts only in-window time', () {
      final rows = aggregateUsage(
        [ev('a', 0, 10 * 60 * 1000)], // bg at 00:10
        openSessions: {'a': -3600 * 1000}, // fg 1h before window start
        windowStart: 0,
      );
      final a = rows.firstWhere((r) => r['package'] == 'a');
      expect(a['fg_ms'], 10 * 60 * 1000);
      expect(a['launches'], 0);
    });

    test('seeded session + in-window fg dup is deduped, spans the window', () {
      final rows = aggregateUsage(
        [
          ev('a', 1, 60 * 60 * 1000), // fg at 01:00
          ev('a', 0, 2 * 60 * 60 * 1000), // bg at 02:00
        ],
        openSessions: {'a': -3600 * 1000}, // fg 1h before window start
        windowStart: 0,
      );
      final a = rows.firstWhere((r) => r['package'] == 'a');
      // app is foreground continuously from window start to 02:00
      expect(a['fg_ms'], 2 * 60 * 60 * 1000);
      expect(a['launches'], 0);
    });

    test('seed closed just after window start contributes its in-window tail',
        () {
      final rows = aggregateUsage(
        [ev('a', 0, 1000)],
        openSessions: {'a': -1000},
        windowStart: 0,
      );
      final a = rows.firstWhere((r) => r['package'] == 'a');
      expect(a['fg_ms'], 1000);
      expect(a['launches'], 0);
    });
  });

  group('compareUsageRows', () {
    Map<String, Object?> row(String pkg, int fg, int launches) => {
      'package': pkg,
      'fg_ms': fg,
      'launches': launches,
    };

    test('sorts by fg_ms descending by default', () {
      final list = [row('a', 100, 3), row('b', 300, 1), row('c', 200, 2)];
      list.sort(
        (x, y) => compareUsageRows(x, y, key: SortKey.time, desc: true),
      );
      expect(list.map((r) => r['package']).toList(), ['b', 'c', 'a']);
    });

    test('sorts by fg_ms ascending', () {
      final list = [row('a', 100, 3), row('b', 300, 1)];
      list.sort(
        (x, y) => compareUsageRows(x, y, key: SortKey.time, desc: false),
      );
      expect(list.map((r) => r['package']).toList(), ['a', 'b']);
    });

    test('sorts by launches descending', () {
      final list = [row('a', 100, 3), row('b', 300, 1), row('c', 200, 2)];
      list.sort(
        (x, y) => compareUsageRows(x, y, key: SortKey.launches, desc: true),
      );
      expect(list.map((r) => r['package']).toList(), ['a', 'c', 'b']);
    });

    test('equal keys are stable (returns 0)', () {
      final list = [row('a', 100, 3), row('b', 100, 3)];
      list.sort(
        (x, y) => compareUsageRows(x, y, key: SortKey.time, desc: true),
      );
      expect(list.map((r) => r['package']).toList(), ['a', 'b']);
    });
  });

  group('RevokeService.buildRevokeMessage', () {
    const owner = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
    const tokenAccount = '11111111111111111111111111111111';
    const tokenAccount2 = 'So11111111111111111111111111111111111111112';
    const blockhash = 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k';

    test('builds non-empty, well-formed bytes (1 required signature)', () {
      final bytes = RevokeService.buildRevokeMessage(
        ownerAddress: owner,
        tokenAccount: tokenAccount,
        blockhash: blockhash,
      );
      expect(bytes, isNotEmpty);
      // Transaction wire format: signature count, one zeroed 64-byte slot for
      // the wallet to fill, then the message.
      expect(bytes.first, 1);
      expect(bytes.sublist(1, 65), everyElement(0));
      expect(bytes.length, greaterThan(65));
    });

    test('is deterministic for identical inputs', () {
      final a = RevokeService.buildRevokeMessage(
        ownerAddress: owner,
        tokenAccount: tokenAccount,
        blockhash: blockhash,
      );
      final b = RevokeService.buildRevokeMessage(
        ownerAddress: owner,
        tokenAccount: tokenAccount,
        blockhash: blockhash,
      );
      expect(a, b);
    });

    test('different token account yields different bytes', () {
      final a = RevokeService.buildRevokeMessage(
        ownerAddress: owner,
        tokenAccount: tokenAccount,
        blockhash: blockhash,
      );
      final b = RevokeService.buildRevokeMessage(
        ownerAddress: owner,
        tokenAccount: tokenAccount2,
        blockhash: blockhash,
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects an owner address of the wrong length', () {
      expect(
        () => RevokeService.buildRevokeMessage(
          ownerAddress: 'short',
          tokenAccount: tokenAccount,
          blockhash: blockhash,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AssetInfo.uiAmount', () {
    AssetInfo asset(String balance, int decimals) => AssetInfo(
      id: 'mint',
      interface: 'FungibleToken',
      name: '',
      symbol: '',
      balance: balance,
      decimals: decimals,
      burnt: false,
      compressed: false,
    );

    test('formats decimal amounts', () {
      expect(asset('123456789', 6).uiAmount, '123.456789');
      expect(asset('1000000', 6).uiAmount, '1');
      expect(asset('250000', 6).uiAmount, '0.25');
      expect(asset('150000', 6).uiAmount, '0.15');
      expect(asset('123', 3).uiAmount, '0.123');
      expect(asset('123', 2).uiAmount, '1.23');
      expect(asset('1', 6).uiAmount, '0.000001');
    });

    test('zero balance and zero decimals', () {
      expect(asset('0', 6).uiAmount, '0');
      expect(asset('42', 0).uiAmount, '42');
    });

    test('preserves precision beyond 2^53', () {
      // 2^53 + 1 cannot be represented as a double; must stay exact.
      expect(asset('9007199254740993', 6).uiAmount, '9007199254.740993');
    });
  });

  group('SkrResolver', () {
    test('hashName uses the ALT Name Service prefix', () {
      final expected = crypto.sha256
          .convert(utf8.encode('ALT Name Servicealice'))
          .bytes;
      expect(SkrResolver.hashName('alice'), Uint8List.fromList(expected));
      expect(SkrResolver.hashName('alice').length, 32);
    });

    test('parseNameRecordOwner decodes owner at offset 40', () {
      final buf = Uint8List(200);
      buf[40] = 1;
      buf[41] = 2;
      final owner = SkrResolver.parseNameRecordOwner(buf);
      expect(owner, isNotNull);
      expect(owner, base58Encode(Uint8List.fromList(buf.sublist(40, 72))));
    });

    test('parseNameRecordOwner returns null on zero owner', () {
      final buf = Uint8List(200);
      expect(SkrResolver.parseNameRecordOwner(buf), isNull);
    });

    test('parseNameRecordOwner returns null when too short', () {
      expect(SkrResolver.parseNameRecordOwner(Uint8List(10)), isNull);
    });

    test('origin name account derivation matches the ANS root', () async {
      expect(
        await SkrResolver.originNameAccountKey(),
        '3mX9b4AZaQehNoQGfckVcmgmA6bkBoFcbLj9RMmMyNcU',
      );
    });
  });

  group('isSkrDomain', () {
    test('detects .skr domains', () {
      expect(WalletAuthService.isSkrDomain('alice.skr'), isTrue);
      expect(WalletAuthService.isSkrDomain('  My.Domain.SKR  '), isTrue);
      expect(WalletAuthService.isSkrDomain('a.skr'), isTrue);
      expect(WalletAuthService.isSkrDomain('.skr'), isFalse); // bare TLD
      expect(WalletAuthService.isSkrDomain('base58address'), isFalse);
      expect(WalletAuthService.isSkrDomain('alice.skr extra'), isFalse);
    });
  });

  group('rpc config', () {
    tearDown(() => rpcOverride = null);

    test('falls back to public RPC when no key is available', () {
      expect(rpcUrl(), publicRpcUrl);
    });

    test('builds the Helius endpoint from the key', () {
      expect(
        rpcUrl(apiKey: 'K'),
        'https://mainnet.helius-rpc.com/?api-key=K',
      );
    });

    test('rpcOverride wins over the key', () {
      rpcOverride = 'https://override.example/';
      expect(rpcUrl(apiKey: 'K'), 'https://override.example/');
    });
  });

  group('rpc hardening', () {
    late HttpServer server;
    int totalRequests = 0;
    int priceHits = 0;
    String? lastUserAgent;
    int failNextPostsWith = 0;
    int failStatus = 429;
    String balanceBody = '{"result":{"value":12345}}';
    String tokenAccountsBody = '{"result":{"value":[]}}';
    String multipleAccountsBody = '{"result":{"value":[]}}';
    int priceStatus = 200;
    String priceBody = '{"data":{}}';

    /// A real-shaped SPL token account: 165 bytes, no delegate, no close
    /// authority, not native, state = Initialized.
    Uint8List emptyAccount(int amount) {
      final b = Uint8List(165);
      b.setRange(0, 32, List.filled(32, 7)); // mint
      b.setRange(32, 64, List.filled(32, 9)); // owner
      for (var i = 0; i < 8; i++) {
        b[64 + i] = (amount >> (8 * i)) & 0xff;
      }
      b[108] = 1; // state: Initialized
      return b;
    }

    setUp(() async {
      totalRequests = 0;
      priceHits = 0;
      lastUserAgent = null;
      failNextPostsWith = 0;
      failStatus = 429;
      balanceBody = '{"result":{"value":12345}}';
      tokenAccountsBody = '{"result":{"value":[]}}';
      multipleAccountsBody = '{"result":{"value":[]}}';
      priceStatus = 200;
      priceBody = '{"data":{}}';
      server = await HttpServer.bind('127.0.0.1', 0);
      final endpoint = 'http://127.0.0.1:${server.port}';
      rpcOverride = endpoint;
      priceApiOverride = endpoint;
      server.listen((req) async {
        lastUserAgent = req.headers.value('user-agent');
        totalRequests++;
        if (req.method == 'GET') {
          priceHits++;
          req.response.statusCode = priceStatus;
          req.response.write(priceBody);
          await req.response.close();
          return;
        }
        if (failNextPostsWith > 0) {
          failNextPostsWith--;
          req.response.statusCode = failStatus;
          req.response.write('');
          await req.response.close();
          return;
        }
        final body = await utf8.decoder.bind(req).join();
        final j = jsonDecode(body) as Map<String, dynamic>;
        final method = j['method'] as String? ?? '';
        final params = j['params'];
        late String response;
        if (method == 'getBalance') {
          response = balanceBody;
        } else if (method == 'getTokenAccountsByOwner') {
          final p1 = params is List && params.length > 1 ? params[1] : null;
          final pid = p1 is Map ? p1['programId'] : null;
          response = pid == SolScanService.token2022Program
              ? '{"result":{"value":[]}}'
              : tokenAccountsBody;
        } else if (method == 'getMultipleAccounts') {
          response = multipleAccountsBody;
        } else {
          response = '{"result":null}';
        }
        req.response.statusCode = 200;
        req.response.write(response);
        await req.response.close();
      });
    });

    tearDown(() async {
      rpcOverride = null;
      priceApiOverride = null;
      await server.close();
    });

    test('getTokenAccountsRaw: unexpected value shape -> []', () async {
      tokenAccountsBody = '{"result":{"value":"unexpected"}}';
      expect(
        await SolScanService.instance.getTokenAccountsRaw('a1'),
        isEmpty,
      );
      tokenAccountsBody = '{"result":{"value":null}}';
      expect(
        await SolScanService.instance.getTokenAccountsRaw('a2'),
        isEmpty,
      );
    });

    test('scanDelegates: malformed items skipped, valid kept', () async {
      tokenAccountsBody = jsonEncode({
        'result': {
          'value': [
            {'pubkey': 123},
            {'pubkey': 'x', 'account': {'data': 'not-a-list'}},
            {
              'pubkey': 'acc1',
              'account': {
                'data': [base64Encode(emptyAccount(999)), 'base64'],
              },
            },
          ],
        },
      });
      final out = await SolScanService.instance.scanDelegates('scan1');
      expect(out, hasLength(1));
      expect(out.first.pubkey, 'acc1');
    });

    test('getAssets: no token accounts -> []', () async {
      tokenAccountsBody = '{"result":{"value":[]}}';
      expect(await SolScanService.instance.getAssets('g1'), isEmpty);
    });

    test('getAssets: unexpected shapes are skipped, not fatal', () async {
      tokenAccountsBody = '{"result":{"value":"nope"}}';
      expect(await SolScanService.instance.getAssets('g2'), isEmpty);
      tokenAccountsBody = '{"result":{"value":[{"pubkey":1}]}}';
      expect(await SolScanService.instance.getAssets('g3'), isEmpty);
    });

    test('getMultipleAccountsBytes: nulls for missing accounts', () async {
      multipleAccountsBody = '{"result":{"value":[null,null]}}';
      final out = await SolScanService.instance.getMultipleAccountsBytes(
        ['a', 'b'],
      );
      expect(out, hasLength(2));
      expect(out, everyElement(isNull));
    });

    test('getBalanceLamports: clear error, not a TypeError', () async {
      balanceBody = '{"result":{"value":"unexpected"}}';
      await expectLater(
        SolScanService.instance.getBalanceLamports('b1'),
        throwsFormatException,
      );
      balanceBody = '{"result":null}';
      await expectLater(
        SolScanService.instance.getBalanceLamports('b2'),
        throwsFormatException,
      );
    });

    test('price feed error -> null (no more silent {})', () async {
      priceStatus = 500;
      expect(await SolScanService.instance.getPrices(['p1']), isNull);
      priceStatus = 200;
      priceBody = 'not json';
      expect(await SolScanService.instance.getPrices(['p2']), isNull);
      priceBody = '{"data":{"p3":{"price":"1.5"}}}';
      expect(await SolScanService.instance.getPrices(['p3']), {'p3': 1.5});
      expect(await SolScanService.instance.getPrices(['p3']), {'p3': 1.5});
      expect(priceHits, 4); // 500x2 (retried), bad-json x1, success x1
    });

    test('price feed network error -> null', () async {
      priceApiOverride = 'http://127.0.0.1:1/';
      expect(await SolScanService.instance.getPrices(['p9']), isNull);
    });

    test('POST retry: 429 then success (backoff)', () async {
      failNextPostsWith = 1;
      failStatus = 429;
      final before = totalRequests;
      final v = await SolScanService.instance.getBalanceLamports('r1');
      expect(v, 12345);
      expect(totalRequests - before, 2);
    });

    test('POST retry: 5xx then success (backoff)', () async {
      failNextPostsWith = 1;
      failStatus = 503;
      final before = totalRequests;
      final v = await SolScanService.instance.getBalanceLamports('r2');
      expect(v, 12345);
      expect(totalRequests - before, 2);
    });

    test('POST no retry on 400', () async {
      failNextPostsWith = 1;
      failStatus = 400;
      final before = totalRequests;
      await expectLater(
        SolScanService.instance.getBalanceLamports('r3'),
        throwsA(isA<Exception>()),
      );
      expect(totalRequests - before, 1);
    });

    test('assets cached within 30s', () async {
      tokenAccountsBody = '{"result":{"value":[]}}';
      final before = totalRequests;
      final a1 = await SolScanService.instance.getAssets('cache1');
      final firstCallRequests = totalRequests - before;
      final a2 = await SolScanService.instance.getAssets('cache1');
      expect(a1, a2);
      expect(
        totalRequests - before,
        firstCallRequests,
        reason: 'the second call must be served from cache',
      );
    });

    test('User-Agent header sent on every call', () async {
      await SolScanService.instance.getBalanceLamports('ua1');
      await SolScanService.instance.getPrices(['ua2']);
      expect(lastUserAgent, 'device_stats/1.0');
    });

    test('programName: short ids no RangeError', () {
      expect(SolScanService.programName('abc'), 'abc');
      expect(SolScanService.programName('abcdefgh'), 'abcdefgh');
      expect(SolScanService.programName('abcdefghijkl'), 'abcdefgh…');
      expect(
        SolScanService.programName(SolScanService.tokenProgram),
        'SPL Token',
      );
    });
  });

  group('TxInfo', () {
    test('fromMap decodes both blockTime and block_time', () {
      final m1 = {
        'signature': 'sig1',
        'slot': 100,
        'err': null,
        'blockTime': 123456789,
        'memo': 'hello',
      };
      final m2 = {
        'signature': 'sig2',
        'slot': 101,
        'err': 'error',
        'block_time': 987654321,
        'memo': null,
      };

      final t1 = TxInfo.fromMap(m1);
      final t2 = TxInfo.fromMap(m2);

      expect(t1.signature, 'sig1');
      expect(t1.slot, 100);
      expect(t1.blockTime, 123456789);
      expect(t1.memo, 'hello');

      expect(t2.signature, 'sig2');
      expect(t2.slot, 101);
      expect(t2.err, 'error');
      expect(t2.blockTime, 987654321);
      expect(t2.memo, isNull);
    });
  });
}
