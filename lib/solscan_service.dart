import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'base58.dart';
import 'rpc_config.dart';

/// Test/override hook for the Jupiter price endpoint (mirrors rpcOverride).
String? priceApiOverride;

/// Minimal Solana RPC client for security scanning (read-only).
/// Scans token accounts and reports active delegates (token approvals) —
/// the Solana equivalent of Revoke.cash (Ethereum ERC-20 approvals).
class SolScanService {
  const SolScanService._();
  static const SolScanService instance = SolScanService._();

  static const String _priceApi = 'https://api.jup.ag/price/v2';
  static final Map<String, _CacheEntry<Map<String, double>>> _priceCache =
      {};
  static final Map<String, _CacheEntry<List<AssetInfo>>> _assetsCache = {};

  static const String tokenProgram =
      'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const String token2022Program =
      'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
  static const String solMint = 'So11111111111111111111111111111111111111112';

  /// Well-known program IDs -> human-readable protocol name.
  static const Map<String, String> knownPrograms = {
    'ComputeBudget111111111111111111111111111111': 'Compute Budget',
    '11111111111111111111111111111111': 'System Program',
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA': 'SPL Token',
    'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb': 'Token-2022',
    'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL': 'Associated Token',
    'JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4': 'Jupiter Aggregator',
    'JUP4Fb2cqiRUcaTHdrPC8h2gNsA2ETXiPDD33WcGuJB': 'Jupiter v4',
    'JUP2jxvXaqu7NQY1GmNF4m1vodw12LVXYxbFLiJvoYef': 'Jupiter v3',
    'routeUGWgWzqBWFcrCfv8tritsqukccJPu3q5Gj3GUx': 'Jupiter Router',
    'METAewPFTN9UzsYwW5hWzJpVhV6VZtZkZiKSTEXzTQ8J': 'Meteora',
    'LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo': 'Meteora DLMM',
    'Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB': 'Meteora Pools',
    'CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK': 'Raydium CLMM',
    '675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8': 'Raydium AMM',
    '9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP': 'Orca v2',
    'whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc': 'Orca Whirlpool',
    'KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD': 'Kamino Lending',
    '6LtLpnUF1Af2QWnYxbmJYr99nc4afWx9FTuDgCNGKfBDJ': 'Kamino Vault',
    'MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD': 'Marinade Staking',
    'jupSoLaHXQiZZTSfEWMTRRgpnyFm8f6sZcosWBQoCpD': 'Jito Staking',
    'Stake11111111111111111111111111111111111111': 'Stake Program',
    'SysvarRent111111111111111111111111111111111': 'Rent Sysvar',
    'SKRskrmtL83pcL4YqLWt6iPefDqwXQWHSw9S9vz94BZ': 'Seeker (SKR)',
  };

  static String programName(String id) {
    final known = knownPrograms[id];
    if (known != null) return known;
    return id.length <= 8 ? id : '${id.substring(0, 8)}…';
  }

  Future<Map<String, dynamic>> _call(
    String method,
    List<dynamic> params,
  ) async {
    return _post(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      }),
    );
  }

  /// RPC call where params is a single JSON object (Helius DAS API shape).
  Future<Map<String, dynamic>> _callObj(
    String method,
    Map<String, dynamic> params,
  ) async {
    return _post(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      }),
    );
  }

  static const String _userAgent = 'device_stats/1.0';
  static const Duration _backoff = Duration(milliseconds: 500);

  /// Sends [request], retrying once after [_backoff] on 429/5xx.
  Future<http.Response> _withRetry(
    Future<http.Response> Function() request,
  ) async {
    http.Response? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future.delayed(_backoff);
      final resp = await request();
      last = resp;
      if (resp.statusCode == 200) return resp;
      if (resp.statusCode != 429 && resp.statusCode < 500) break;
    }
    return last!;
  }

  Future<Map<String, dynamic>> _post(String body) async {
    final resp = await _withRetry(
      () => http
          .post(
            Uri.parse(rpcUrl()),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20)),
    );
    if (resp.statusCode != 200) {
      throw Exception('RPC HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body);
    final envelope = json is Map<String, dynamic> ? json : null;
    if (envelope == null) {
      throw FormatException('RPC: unexpected response');
    }
    if (envelope['error'] != null) {
      throw Exception('RPC error: ${envelope['error']}');
    }
    final result = envelope['result'];
    if (result is! Map<String, dynamic>) {
      throw FormatException('RPC: unexpected result shape');
    }
    return result;
  }

  /// RPC call whose result is a JSON array (e.g. getSignaturesForAddress).
  Future<List<dynamic>> _callList(String method, List<dynamic> params) async {
    final resp = await _withRetry(
      () => http
          .post(
            Uri.parse(rpcUrl()),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': method,
              'params': params,
            }),
          )
          .timeout(const Duration(seconds: 20)),
    );
    if (resp.statusCode != 200) {
      throw Exception('RPC HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body);
    final envelope = json is Map<String, dynamic> ? json : null;
    if (envelope == null) {
      throw FormatException('RPC: unexpected response');
    }
    if (envelope['error'] != null) {
      throw Exception('RPC error: ${envelope['error']}');
    }
    final result = envelope['result'];
    if (result is! List) {
      throw FormatException('RPC: unexpected result list');
    }
    return result;
  }

  /// SOL balance (lamports).
  Future<int> getBalanceLamports(String address) async {
    final r = await _call('getBalance', [address]);
    final value = r['value'];
    if (value is! num) {
      throw FormatException('getBalance: unexpected value shape');
    }
    return value.toInt();
  }

  /// Raw account data (decoded from base64) for an address, or null if the
  /// account does not exist.
  Future<Uint8List?> getAccountInfoBytes(String address) async {
    final r = await _call('getAccountInfo', [
      address,
      {'encoding': 'base64'},
    ]);
    final value = r['value'];
    if (value is! Map) return null;
    final data = value['data'];
    if (data is List && data.isNotEmpty && data[0] is String) {
      return base64Decode(data[0] as String);
    }
    return null;
  }

  /// Owner of the largest token account for a mint, resolved through the
  /// parsed token-account schema. Returns a base58 address or null.
  Future<String?> getTokenLargestOwner(String mint) async {
    final r = await _call('getTokenLargestAccounts', [mint]);
    final value = r['value'];
    if (value is! List || value.isEmpty) return null;
    final top = value.first;
    if (top is! Map) return null;
    final addr = top['address'];
    if (addr is! String) return null;
    final pr = await _call('getAccountInfo', [
      addr,
      {'encoding': 'jsonParsed'},
    ]);
    final pv = pr['value'];
    if (pv is! Map) return null;
    final parsed = pv['data'];
    if (parsed is! Map) return null;
    final info = parsed['parsed'];
    if (info is! Map) return null;
    final inner = info['info'];
    if (inner is! Map) return null;
    final owner = inner['owner'];
    return owner is String ? owner : null;
  }

  /// USD prices for the given mints via Jupiter's price API.
  /// Returns mint -> price (USD); null when the price feed is unavailable
  /// (callers must surface a "prices unavailable" state, not {}-silence).
  /// Tokens without a market are omitted. Results are cached for 30s.
  Future<Map<String, double>?> getPrices(List<String> mints) async {
    final unique = mints.where((m) => m.isNotEmpty).toSet().toList()..sort();
    if (unique.isEmpty) return {};
    final key = unique.join(',');
    final cached = _priceCache[key];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.value;
    }
    try {
      final url = Uri.parse(
        '${priceApiOverride ?? _priceApi}?ids=${unique.join(',')}',
      );
      final resp = await _withRetry(
        () => http
            .get(url, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 20)),
      );
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return null;
      final data = json['data'];
      final dataMap = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final out = <String, double>{};
      for (final m in unique) {
        final entry = dataMap[m];
        if (entry is Map) {
          final p = entry['price'];
          final d = p is num
              ? p.toDouble()
              : (p is String ? double.tryParse(p) : null);
          if (d != null) out[m] = d;
        }
      }
      _priceCache[key] = _CacheEntry(
        out,
        DateTime.now().add(const Duration(seconds: 30)),
      );
      return out;
    } catch (e) {
      log('getPrices error: $e');
      return null;
    }
  }

  /// All token accounts for a wallet (raw base64 data for delegate parsing).
  Future<List<Map<String, dynamic>>> getTokenAccountsRaw(
    String address, {
    String programId = tokenProgram,
  }) async {
    final r = await _call('getTokenAccountsByOwner', [
      address,
      {'programId': programId},
      {'encoding': 'base64'},
    ]);
    final value = r['value'];
    if (value is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final it in value) {
      if (it is Map<String, dynamic>) out.add(it);
    }
    return out;
  }

  /// All token accounts for a wallet across legacy SPL Token and Token-2022.
  Future<List<Map<String, dynamic>>> getAllTokenAccountsRaw(
    String address,
  ) async {
    final legacy = await getTokenAccountsRaw(address);
    final token2022 = await getTokenAccountsRaw(
      address,
      programId: token2022Program,
    );
    return <Map<String, dynamic>>[...legacy, ...token2022];
  }

  /// Rich asset list via Helius DAS (fungible tokens + NFTs with metadata).
  /// Results are cached for 30s per address.
  ///
  /// Returns `[]` (empty) when running against a non-DAS RPC (no Helius key)
  /// — token/NFT metadata simply comes back empty rather than erroring.
  Future<List<AssetInfo>> getAssets(String address) async {
    if (!dasAvailable) return [];
    final cached = _assetsCache[address];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.value;
    }
    final r = await _callObj('getAssetsByOwner', {
      'ownerAddress': address,
      'page': 1,
      'limit': 1000,
      'displayOptions': {'showFungible': true},
    });
    final items = r['items'];
    final out = <AssetInfo>[];
    if (items is List) {
      for (final it in items) {
        if (it is! Map<String, dynamic>) continue;
        final m = it;
        final content = m['content'];
        final metaRaw = content is Map ? content['metadata'] : null;
        final meta = metaRaw is Map ? metaRaw : const <String, dynamic>{};
        final tokenInfoRaw = m['token_info'];
        final tokenInfo =
            tokenInfoRaw is Map ? tokenInfoRaw : const <String, dynamic>{};
        final id = m['id'];
        final iface = m['interface'];
        final name = meta['name'];
        final symbol = meta['symbol'];
        final balance = tokenInfo['balance'];
        final decimals = tokenInfo['decimals'];
        final compRaw = m['compression'];
        final compressed = compRaw is Map ? compRaw['compressed'] : null;
        out.add(
          AssetInfo(
            id: id is String ? id : '',
            interface: iface is String ? iface : '',
            name: name is String ? name : '',
            symbol: symbol is String ? symbol : '',
            balance: balance == null ? '' : balance.toString(),
            decimals: decimals is num ? decimals.toInt() : 0,
            burnt: m['burnt'] == true,
            compressed: compressed == true,
          ),
        );
      }
    }
    _assetsCache[address] =
        _CacheEntry(out, DateTime.now().add(const Duration(seconds: 30)));
    return out;
  }

  /// Recent transaction signatures (and status) for an address.
  Future<List<TxInfo>> getSignatures(String address, {int limit = 10}) async {
    final list = await _callList('getSignaturesForAddress', [
      address,
      {'limit': limit},
    ]);
    final out = <TxInfo>[];
    for (final m in list) {
      if (m is! Map<String, dynamic>) continue;
      final mm = m;
      final signature = mm['signature'];
      final slot = mm['slot'];
      final blockTime = mm['blockTime'];
      final memo = mm['memo'];
      out.add(
        TxInfo(
          signature: signature is String ? signature : '',
          slot: slot is num ? slot.toInt() : 0,
          err: mm['err'],
          blockTime: blockTime is num ? blockTime.toInt() : 0,
          memo: memo is String ? memo : null,
        ),
      );
    }
    return out;
  }

  /// Enriched details for a single signature: fee (SOL), involved program
  /// names, all parsed SPL token transfers and native SOL transfers.
  Future<TxDetail> getTransactionDetail(String signature) async {
    final r = await _call('getTransaction', [
      signature,
      {'encoding': 'jsonParsed', 'maxSupportedTransactionVersion': 0},
    ]);
    final metaRaw = r['meta'];
    final meta = metaRaw is Map ? metaRaw : const <String, dynamic>{};
    final feeRaw = meta['fee'];

    final transactionRaw = r['transaction'];
    final transaction = transactionRaw is Map
        ? transactionRaw
        : const <String, dynamic>{};
    final messageRaw = transaction['message'];
    final message = messageRaw is Map ? messageRaw : const <String, dynamic>{};
    final instructionsRaw = message['instructions'];
    final instructions = instructionsRaw is List
        ? instructionsRaw
        : const <dynamic>[];

    final programs = <String>[];
    final transfers = <TransferDetail>[];
    final solTransfers = <SolTransferDetail>[];

    for (final ix in instructions) {
      if (ix is! Map<String, dynamic>) continue;
      final m = ix;
      final pid = m['programId'];
      if (pid is String && pid.isNotEmpty && !programs.contains(pid)) {
        programs.add(pid);
      }
      final parsed = m['parsed'];
      if (parsed is Map) {
        final type = parsed['type'];
        final infoRaw = parsed['info'];
        final info = infoRaw is Map ? infoRaw : const <String, dynamic>{};
        if (type == 'transfer' || type == 'transferChecked') {
          final lamports = info['lamports'];
          final amount = info['amount'];
          final destination = info['destination'];
          final source = info['source'];
          final mint = info['mint'];
          if (lamports is num) {
            solTransfers.add(
              SolTransferDetail(
                destination: destination is String ? destination : '',
                source: source is String ? source : '',
                lamports: lamports.toInt(),
              ),
            );
          } else if (amount != null) {
            transfers.add(
              TransferDetail(
                mint: mint is String ? mint : '',
                amount: amount.toString(),
                destination: destination is String ? destination : '',
                source: source is String ? source : '',
              ),
            );
          }
        }
      }
    }

    return TxDetail(
      feeLamports: feeRaw is num ? feeRaw.toInt() : 0,
      programs: programs,
      transfers: transfers,
      solTransfers: solTransfers,
    );
  }

  /// Parsed token account with delegate info.
  Future<List<TokenAccountInfo>> scanDelegates(String address) async {
    final raw = await getAllTokenAccountsRaw(address);
    final out = <TokenAccountInfo>[];
    for (final item in raw) {
      final pubkey = item['pubkey'];
      if (pubkey is! String) continue;
      final account = item['account'];
      if (account is! Map) continue;
      final data = account['data'];
      if (data is! List || data.isEmpty || data[0] is! String) continue;
      final info = parseTokenAccount(base64Decode(data[0] as String));
      if (info != null) {
        info.pubkey = pubkey;
        out.add(info);
      }
    }
    return out;
  }
}

/// One in-memory cache entry with an expiry.
class _CacheEntry<T> {
  final T value;
  final DateTime expires;
  _CacheEntry(this.value, this.expires);
}

/// Borsh decode of an SPL Token Account base layout.
///
/// Little-endian, no padding; Option fields are 1-byte tags
/// (0x00 = None, 0x01 = Some). The base struct is 92 bytes when empty,
/// 124 with one Option populated, and 156 with both populated.
/// Token-2022 accounts append extension data after the base struct,
/// which is ignored here.
TokenAccountInfo? parseTokenAccount(Uint8List d) {
  if (d.length < 92) return null;
  int c = 0;
  final mint = base58Encode(d.sublist(c, c + 32));
  c += 32;
  final owner = base58Encode(d.sublist(c, c + 32));
  c += 32;
  final amount = _readU64(d, c);
  c += 8;
  final delegateTag = d[c];
  c += 1;
  String? delegate;
  if (delegateTag == 1) {
    if (c + 32 > d.length) return null;
    delegate = base58Encode(d.sublist(c, c + 32));
    c += 32;
  }
  final state = d[c];
  c += 1;
  final delegatedAmount = _readU64(d, c);
  c += 8;
  final closeAuthorityTag = d[c];
  c += 1;
  String? closeAuthority;
  if (closeAuthorityTag == 1) {
    if (c + 32 > d.length) return null;
    closeAuthority = base58Encode(d.sublist(c, c + 32));
    c += 32;
  }
  final isNative = d[c] != 0;
  c += 1;
  if (c + 8 > d.length) return null;
  final nativeAmount = _readU64(d, c);
  return TokenAccountInfo(
    mint: mint,
    owner: owner,
    amount: amount,
    delegate: delegate,
    state: state,
    delegatedAmount: delegatedAmount,
    closeAuthority: closeAuthority,
    isNative: isNative,
    nativeAmount: nativeAmount,
  );
}

int _readU64(Uint8List d, int off) {
  int v = 0;
  for (int i = 0; i < 8; i++) {
    v |= d[off + i] << (8 * i);
  }
  return v;
}

class TokenAccountInfo {
  String pubkey = '';
  final String mint;
  final String owner;
  final int amount;
  final String? delegate;
  final int state;
  final int delegatedAmount;
  final String? closeAuthority;
  final bool isNative;
  final int nativeAmount;

  TokenAccountInfo({
    required this.mint,
    required this.owner,
    required this.amount,
    required this.delegate,
    required this.state,
    required this.delegatedAmount,
    this.closeAuthority,
    required this.isNative,
    required this.nativeAmount,
  });

  bool get hasDelegate => delegate != null && delegate!.isNotEmpty;

  bool get hasCloseAuthority =>
      closeAuthority != null && closeAuthority!.isNotEmpty;
}

/// A single asset (fungible token or NFT) from Helius DAS.
class AssetInfo {
  final String id; // mint address (fungible) or asset id (NFT)
  final String interface;
  final String name;
  final String symbol;
  final String balance; // raw string
  final int decimals;
  final bool burnt;
  final bool compressed;

  AssetInfo({
    required this.id,
    required this.interface,
    required this.name,
    required this.symbol,
    required this.balance,
    required this.decimals,
    required this.burnt,
    required this.compressed,
  });

  bool get isFungible =>
      interface == 'FungibleToken' || interface == 'FungibleAsset';

  /// Human-readable UI amount (balance / 10^decimals).
  String get uiAmount {
    final b = int.tryParse(balance);
    if (b == null) return balance;
    if (decimals <= 0) return b.toString();
    return _formatUnits(b, decimals);
  }

  static final BigInt _ten = BigInt.from(10);

  /// Integer-based formatting to avoid double-precision loss on large balances.
  static String _formatUnits(int raw, int decimals) {
    final factor = _ten.pow(decimals);
    final rawBig = BigInt.from(raw);
    final whole = rawBig ~/ factor;
    final frac = rawBig % factor;
    if (frac == BigInt.zero) return whole.toString();
    var fracStr = frac.toString().padLeft(decimals, '0');
    fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fracStr';
  }
}

/// A single transaction signature record.
class TxInfo {
  final String signature;
  final int slot;
  final Object? err;
  final int blockTime;
  final String? memo;

  TxInfo({
    required this.signature,
    required this.slot,
    required this.err,
    required this.blockTime,
    required this.memo,
  });

  bool get hasError => err != null;
}

/// Enriched transaction details for display.
class TxDetail {
  final int feeLamports;
  final List<String> programs;
  final List<TransferDetail> transfers;
  final List<SolTransferDetail> solTransfers;

  TxDetail({
    required this.feeLamports,
    required this.programs,
    required this.transfers,
    required this.solTransfers,
  });

  String get feeSol => (feeLamports / 1e9).toStringAsFixed(6);

  /// Human-readable program names (known protocols, else shortened address).
  List<String> get programLabels =>
      programs.map(SolScanService.programName).toList();
}

/// A parsed SPL token transfer.
class TransferDetail {
  final String mint;
  final String amount;
  final String destination;
  final String source;

  TransferDetail({
    required this.mint,
    required this.amount,
    required this.destination,
    required this.source,
  });
}

/// A parsed native SOL transfer (system program).
class SolTransferDetail {
  final String destination;
  final String source;
  final int lamports;

  SolTransferDetail({
    required this.destination,
    required this.source,
    required this.lamports,
  });

  String get solAmount => (lamports / 1e9).toStringAsFixed(4);
}
