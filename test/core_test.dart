import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/base58.dart' as sol_base58;

import 'package:device_stats/base58.dart';
import 'package:device_stats/domains.dart';
import 'package:device_stats/rpc_config.dart';
import 'package:device_stats/solscan_service.dart';
import 'package:device_stats/stats_db.dart';
import 'package:device_stats/revoke.dart';
import 'package:device_stats/main.dart';
import 'package:device_stats/wallet_auth.dart';

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
    List<int> u64le(int v) =>
        List<int>.generate(8, (i) => (v >> (8 * i)) & 0xff);

    Uint8List build({
      int amount = 0,
      int delegatedAmount = 0,
      int delegateTag = 0,
      List<int>? delegate,
      int state = 1,
      int closeAuthorityTag = 0,
      List<int>? closeAuthority,
      bool isNative = false,
      int nativeAmount = 0,
    }) {
      final bytes = <int>[
        ...List.filled(32, 7), // mint
        ...List.filled(32, 9), // owner
        ...u64le(amount),
        delegateTag,
        if (delegateTag == 1) ...(delegate ?? List.filled(32, 5)),
        state,
        ...u64le(delegatedAmount),
        closeAuthorityTag,
        if (closeAuthorityTag == 1) ...(closeAuthority ?? List.filled(32, 8)),
        isNative ? 1 : 0,
        ...u64le(nativeAmount),
      ];
      return Uint8List.fromList(bytes);
    }

    test('returns null when too short', () {
      expect(parseTokenAccount(Uint8List(91)), isNull);
    });

    test('decodes an empty account (92 bytes)', () {
      final d = build(amount: 123456, state: 1, delegatedAmount: 999);
      expect(d.length, 92);
      final info = parseTokenAccount(d)!;
      expect(info.amount, 123456);
      expect(info.delegate, isNull);
      expect(info.hasDelegate, isFalse);
      expect(info.state, 1);
      expect(info.delegatedAmount, 999);
      expect(info.closeAuthority, isNull);
      expect(info.hasCloseAuthority, isFalse);
      expect(info.isNative, isFalse);
      expect(info.nativeAmount, 0);
    });

    test('decodes an account with a delegate (124 bytes)', () {
      final delegate = List<int>.filled(32, 5);
      final d = build(
        amount: 42,
        delegateTag: 1,
        delegate: delegate,
        state: 1,
        delegatedAmount: 7,
      );
      expect(d.length, 124);
      final info = parseTokenAccount(d)!;
      expect(info.delegate, base58Encode(Uint8List.fromList(delegate)));
      expect(info.hasDelegate, isTrue);
      expect(info.delegatedAmount, 7);
    });

    test('decodes an account with a close authority (124 bytes)', () {
      final ca = List<int>.filled(32, 8);
      final d = build(
        amount: 1,
        state: 1,
        delegatedAmount: 0,
        closeAuthorityTag: 1,
        closeAuthority: ca,
      );
      expect(d.length, 124);
      final info = parseTokenAccount(d)!;
      expect(info.hasCloseAuthority, isTrue);
      expect(info.closeAuthority, base58Encode(Uint8List.fromList(ca)));
    });

    test('decodes an account with both options (156 bytes)', () {
      final delegate = List<int>.filled(32, 5);
      final ca = List<int>.filled(32, 8);
      final d = build(
        amount: 1,
        delegateTag: 1,
        delegate: delegate,
        state: 1,
        delegatedAmount: 2,
        closeAuthorityTag: 1,
        closeAuthority: ca,
      );
      expect(d.length, 156);
      final info = parseTokenAccount(d)!;
      expect(info.hasDelegate, isTrue);
      expect(info.hasCloseAuthority, isTrue);
    });

    test('reads is_native and native amount', () {
      final d = build(amount: 5, state: 1, isNative: true, nativeAmount: 777);
      final info = parseTokenAccount(d)!;
      expect(info.isNative, isTrue);
      expect(info.nativeAmount, 777);
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
      // Serialized tx leads with the signature count; a single owner signer
      // (fee payer) requires exactly one signature.
      expect(bytes.first, 1);
      expect(bytes.length, greaterThan(64)); // >= 1 sig (64B) + message
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
    String assetsBody = '{"result":{"items":[]}}';
    int priceStatus = 200;
    String priceBody = '{"data":{}}';

    Uint8List emptyAccount(int amount) {
      return Uint8List.fromList(<int>[
        ...List.filled(32, 7),
        ...List.filled(32, 9),
        ...List.generate(8, (i) => (amount >> (8 * i)) & 0xff),
        0,
        1,
        ...List.filled(8, 0),
        0,
        1,
        0,
        ...List.filled(8, 0),
      ]);
    }

    setUp(() async {
      totalRequests = 0;
      priceHits = 0;
      lastUserAgent = null;
      failNextPostsWith = 0;
      failStatus = 429;
      balanceBody = '{"result":{"value":12345}}';
      tokenAccountsBody = '{"result":{"value":[]}}';
      assetsBody = '{"result":{"items":[]}}';
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
        } else if (method == 'getAssetsByOwner') {
          response = assetsBody;
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

    test('getAssets: unexpected shapes -> []', () async {
      assetsBody = '{"result":{"items":"nope"}}';
      expect(await SolScanService.instance.getAssets('g1'), isEmpty);
      assetsBody = '{"result":{"items":["notamap"]}}';
      expect(await SolScanService.instance.getAssets('g2'), isEmpty);
      assetsBody = '{"result":{"items":[{"id":"m1","token_info":{"balance":"123","decimals":6}}]}}';
      final assets = await SolScanService.instance.getAssets('g3');
      expect(assets, hasLength(1));
      expect(assets.first.id, 'm1');
      expect(assets.first.uiAmount, '0.000123');
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
      assetsBody =
          '{"result":{"items":[{"id":"c1","token_info":{"balance":"5"}}]}}';
      final a1 = await SolScanService.instance.getAssets('cache1');
      final a2 = await SolScanService.instance.getAssets('cache1');
      expect(a1, a2);
      expect(a1.first.id, 'c1');
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
}
