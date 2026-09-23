import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:solana/solana.dart' show Ed25519HDPublicKey;

import 'base58.dart';
import 'package:pipstats/constants.dart';
import 'package:pipstats/rpc_config.dart';

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

  static const String tokenProgram = SolanaConstants.tokenProgram;
  static const String token2022Program = SolanaConstants.token2022Program;
  static const String solMint = SolanaConstants.solMint;

  /// Metaplex Token Metadata program — the on-chain source of token and NFT
  /// names/symbols. Reading it directly replaces Helius DAS and needs no API
  /// key: it works on any RPC, including the free public one.
  static const String metadataProgram =
      'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s';

  static final Map<String, _CacheEntry<TokenMetadata?>> _metadataCache = {};

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
    'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3': 'Seeker (SKR)',
  };

  static String programName(String id) {
    final known = knownPrograms[id];
    if (known != null) return known;
    return id.length <= 8 ? id : '${id.substring(0, 8)}…';
  }

  Future<Map<String, dynamic>> call(
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

  static const String _userAgent = 'device_stats/1.0';
  static const Duration _backoff = SolanaConstants.retryBackoff;

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
          .timeout(SolanaConstants.rpcTimeout),
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
          .timeout(SolanaConstants.rpcTimeout),
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
    final r = await call('getBalance', [address]);
    final value = r['value'];
    if (value is! num) {
      throw FormatException('getBalance: unexpected value shape');
    }
    return value.toInt();
  }

  /// Recent blockhash, required to compile a transaction message.
  /// Uses `finalized` so the hash stays valid for the full MWA round-trip
  /// (the user may take a while to approve in the wallet).
  Future<String> getLatestBlockhash() async {
    final r = await call('getLatestBlockhash', [
      {'commitment': 'finalized'},
    ]);
    final value = r['value'];
    if (value is! Map) {
      throw FormatException('getLatestBlockhash: unexpected value shape');
    }
    final blockhash = value['blockhash'];
    if (blockhash is! String || blockhash.isEmpty) {
      throw FormatException('getLatestBlockhash: missing blockhash');
    }
    return blockhash;
  }

  /// Decimals declared by an SPL Token mint, or null when the account is
  /// missing or too short.
  ///
  /// Mint layout (`spl_token::state::Mint`, fixed 82 bytes):
  /// `mint_authority` `COption<Pubkey>` [0..36), `supply` u64 [36..44),
  /// `decimals` u8 @44, `is_initialized` @45, `freeze_authority` [46..82).
  ///
  /// Never hardcode a token's decimals: `transferChecked` verifies them
  /// on-chain and rejects the instruction on a mismatch, and a wrong value
  /// scales the transferred amount by a power of ten.
  Future<int?> getMintDecimals(String mint) async {
    final data = await getAccountInfoBytes(mint);
    if (data == null || data.length < 45) return null;
    return data[44];
  }

  /// Raw account data (decoded from base64) for an address, or null if the
  /// account does not exist.
  Future<Uint8List?> getAccountInfoBytes(String address) async {
    final r = await call('getAccountInfo', [
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
    final r = await call('getTokenLargestAccounts', [mint]);
    final value = r['value'];
    if (value is! List || value.isEmpty) return null;
    final top = value.first;
    if (top is! Map) return null;
    final addr = top['address'];
    if (addr is! String) return null;
    final pr = await call('getAccountInfo', [
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
            .timeout(SolanaConstants.rpcTimeout),
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
        DateTime.now().add(SolanaConstants.cacheDuration),
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
    final r = await call('getTokenAccountsByOwner', [
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

  /// Raw account data for many addresses in one round-trip.
  /// Returns a list positionally aligned with [addresses]; missing accounts
  /// come back as null. Chunked to stay inside RPC per-request limits.
  Future<List<Uint8List?>> getMultipleAccountsBytes(
    List<String> addresses,
  ) async {
    final out = <Uint8List?>[];
    const chunkSize = 100;
    for (var i = 0; i < addresses.length; i += chunkSize) {
      final chunk = addresses.sublist(
        i,
        i + chunkSize > addresses.length ? addresses.length : i + chunkSize,
      );
      final r = await call('getMultipleAccounts', [
        chunk,
        {'encoding': 'base64'},
      ]);
      final value = r['value'];
      if (value is! List) {
        out.addAll(List<Uint8List?>.filled(chunk.length, null));
        continue;
      }
      for (var j = 0; j < chunk.length; j++) {
        final item = j < value.length ? value[j] : null;
        if (item is! Map) {
          out.add(null);
          continue;
        }
        final data = item['data'];
        if (data is List && data.isNotEmpty && data[0] is String) {
          try {
            out.add(base64Decode(data[0] as String));
          } catch (_) {
            out.add(null);
          }
        } else {
          out.add(null);
        }
      }
    }
    return out;
  }

  /// Metaplex metadata PDA for [mint]: seeds `["metadata", program, mint]`.
  static Future<String> metadataAddress(String mint) async {
    final program = Ed25519HDPublicKey.fromBase58(metadataProgram);
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [
        utf8.encode('metadata'),
        program.bytes,
        Ed25519HDPublicKey.fromBase58(mint).bytes,
      ],
      programId: program,
    );
    return pda.toBase58();
  }

  /// On-chain name/symbol/uri for each mint that has a metadata account.
  /// Mints without metadata are simply absent from the result.
  Future<Map<String, TokenMetadata>> getTokenMetadata(
    List<String> mints,
  ) async {
    final unique = mints.where((m) => m.isNotEmpty).toSet().toList();
    final out = <String, TokenMetadata>{};
    final pending = <String>[];
    final now = DateTime.now();
    for (final mint in unique) {
      final cached = _metadataCache[mint];
      if (cached != null && cached.expires.isAfter(now)) {
        final value = cached.value;
        if (value != null) out[mint] = value;
      } else {
        pending.add(mint);
      }
    }
    if (pending.isEmpty) return out;

    final pdas = <String>[];
    for (final mint in pending) {
      pdas.add(await metadataAddress(mint));
    }
    final accounts = await getMultipleAccountsBytes(pdas);
    // Metadata is effectively immutable for established tokens; an hour of
    // caching keeps the vault from re-reading it on every refresh.
    final expires = DateTime.now().add(const Duration(hours: 1));
    for (var i = 0; i < pending.length; i++) {
      final data = i < accounts.length ? accounts[i] : null;
      final meta = data == null ? null : TokenMetadata.decode(data);
      _metadataCache[pending[i]] = _CacheEntry(meta, expires);
      if (meta != null) out[pending[i]] = meta;
    }
    return out;
  }

  /// Token and NFT holdings for a wallet, assembled entirely from on-chain
  /// reads: token accounts for balances, mint accounts for decimals/supply,
  /// and Metaplex metadata accounts for names and symbols.
  ///
  /// This replaces Helius DAS (`getAssetsByOwner`) and needs no API key.
  /// The one thing it cannot see is compressed NFTs, which live in Merkle
  /// trees rather than accounts and are only exposed through a DAS provider.
  /// Results are cached for 30s per address.
  Future<List<AssetInfo>> getAssets(String address) async {
    final cached = _assetsCache[address];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.value;
    }

    final raw = await getAllTokenAccountsRaw(address);
    final balances = <String, int>{};
    for (final item in raw) {
      final account = item['account'];
      if (account is! Map) continue;
      final data = account['data'];
      if (data is! List || data.isEmpty || data[0] is! String) continue;
      final info = parseTokenAccount(base64Decode(data[0] as String));
      if (info == null || info.amount <= 0) continue;
      balances[info.mint] = (balances[info.mint] ?? 0) + info.amount;
    }
    if (balances.isEmpty) {
      _assetsCache[address] = _CacheEntry(
        const <AssetInfo>[],
        DateTime.now().add(SolanaConstants.cacheDuration),
      );
      return const <AssetInfo>[];
    }

    final mints = balances.keys.toList();
    final mintAccounts = await getMultipleAccountsBytes(mints);
    final metadata = await getTokenMetadata(mints);

    final out = <AssetInfo>[];
    for (var i = 0; i < mints.length; i++) {
      final mint = mints[i];
      final mintData = i < mintAccounts.length ? mintAccounts[i] : null;
      final decimals =
          mintData != null && mintData.length > 44 ? mintData[44] : 0;
      final supply =
          mintData != null && mintData.length >= 44 ? _u64le(mintData, 36) : 0;
      final meta = metadata[mint];
      // A mint with no decimals and a supply of one is an NFT; everything
      // else is treated as fungible.
      final isNft = decimals == 0 && supply == 1;
      out.add(
        AssetInfo(
          id: mint,
          interface: isNft ? 'V1_NFT' : 'FungibleToken',
          name: meta?.name ?? '',
          symbol: meta?.symbol ?? '',
          balance: '${balances[mint]}',
          decimals: decimals,
          burnt: false,
          compressed: false,
        ),
      );
    }
    out.sort((a, b) => a.symbol.compareTo(b.symbol));
    _assetsCache[address] =
        _CacheEntry(out, DateTime.now().add(SolanaConstants.cacheDuration));
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
      out.add(TxInfo.fromMap(m));
    }
    return out;
  }

  /// Enriched details for a single signature: fee (SOL), involved program
  /// names, all parsed SPL token transfers and native SOL transfers.
  Future<TxDetail> getTransactionDetail(String signature) async {
     final r = await call('getTransaction', [
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

/// Byte offsets of the SPL Token account layout (`spl_token::state::Account`).
///
/// The account is serialized with the program's `Pack` impl, **not** Borsh:
/// every field is fixed-width and each `COption` carries a **4-byte** little
/// endian u32 tag (0 = None, 1 = Some) followed by the value, present or not.
/// A live token account is therefore always exactly [size] bytes.
///
/// ```text
///   mint              32  [0..32)
///   owner             32  [32..64)
///   amount             8  [64..72)    u64 LE
///   delegate          36  [72..108)   COption<Pubkey>: tag @72,  key   @76
///   state              1  [108]       0=Uninitialized 1=Initialized 2=Frozen
///   is_native         12  [109..121)  COption<u64>:    tag @109, value @113
///   delegated_amount   8  [121..129)  u64 LE
///   close_authority   36  [129..165)  COption<Pubkey>: tag @129, key   @133
/// ```
///
/// Note the ordering: `is_native` sits **between** `state` and
/// `delegated_amount`. Token-2022 accounts reuse this base and append
/// extensions after byte 165, so a length check must be `>=`, not `==`.
class TokenAccountLayout {
  static const int mint = 0;
  static const int owner = 32;
  static const int amount = 64;
  static const int delegateTag = 72;
  static const int delegate = 76;
  static const int state = 108;
  static const int isNativeTag = 109;
  static const int nativeAmount = 113;
  static const int delegatedAmount = 121;
  static const int closeAuthorityTag = 129;
  static const int closeAuthority = 133;

  /// Serialized size of the base account.
  static const int size = 165;

  TokenAccountLayout._();
}

int _u32le(Uint8List d, int o) =>
    d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);

/// Reads a little-endian u64.
///
/// Dart's `int` is 64-bit **signed**, so a value above 2^63-1 would wrap to a
/// negative number and render as a negative balance. Such supplies are
/// vanishingly rare but not impossible, so the top-bit case is saturated
/// instead: a clamped maximum is wrong by a knowable amount, a negative
/// balance is wrong in a way that looks like a different bug.
int _u64le(Uint8List d, int o) {
  var v = 0;
  for (var i = 0; i < 7; i++) {
    v |= d[o + i] << (8 * i);
  }
  final top = d[o + 7];
  if (top & 0x80 != 0) return 0x7FFFFFFFFFFFFFFF;
  return v | (top << 56);
}

String _pubkey(Uint8List d, int o) => base58Encode(d.sublist(o, o + 32));

/// Decodes an SPL Token (or Token-2022) account from its raw account data.
///
/// Returns null when the buffer is too short to be a token account.
TokenAccountInfo? parseTokenAccount(Uint8List d) {
  if (d.length < TokenAccountLayout.size) return null;
  try {
    final hasDelegate = _u32le(d, TokenAccountLayout.delegateTag) == 1;
    final isNative = _u32le(d, TokenAccountLayout.isNativeTag) == 1;
    final hasClose = _u32le(d, TokenAccountLayout.closeAuthorityTag) == 1;

    return TokenAccountInfo(
      mint: _pubkey(d, TokenAccountLayout.mint),
      owner: _pubkey(d, TokenAccountLayout.owner),
      amount: _u64le(d, TokenAccountLayout.amount),
      delegate: hasDelegate ? _pubkey(d, TokenAccountLayout.delegate) : null,
      state: d[TokenAccountLayout.state],
      delegatedAmount: _u64le(d, TokenAccountLayout.delegatedAmount),
      closeAuthority:
          hasClose ? _pubkey(d, TokenAccountLayout.closeAuthority) : null,
      isNative: isNative,
      nativeAmount: isNative ? _u64le(d, TokenAccountLayout.nativeAmount) : 0,
    );
  } catch (_) {
    return null;
  }
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

/// Name, symbol and metadata URI from a Metaplex Token Metadata account.
///
/// Account layout: `key` u8 @0, `update_authority` @1, `mint` @33, then three
/// Borsh strings — name, symbol, uri. Metaplex pads them with NUL to fixed
/// widths, so trailing NULs are trimmed.
class TokenMetadata {
  final String name;
  final String symbol;
  final String uri;

  const TokenMetadata({
    required this.name,
    required this.symbol,
    required this.uri,
  });

  static TokenMetadata? decode(Uint8List d) {
    try {
      var offset = 1 + 32 + 32;
      String readString() {
        final length = _u32le(d, offset);
        offset += 4;
        if (length > d.length - offset) throw const FormatException('bad len');
        final bytes = d.sublist(offset, offset + length);
        offset += length;
        return utf8
            .decode(bytes, allowMalformed: true)
            .replaceAll('\u0000', '')
            .trim();
      }

      final name = readString();
      final symbol = readString();
      final uri = readString();
      if (name.isEmpty && symbol.isEmpty) return null;
      return TokenMetadata(name: name, symbol: symbol, uri: uri);
    } catch (_) {
      return null;
    }
  }
}

/// A single asset (fungible token or NFT) held by a wallet.
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

  factory AssetInfo.fromMap(Map<String, dynamic> m) {
    final content = m['content'] as Map?;
    final meta = content?['metadata'] as Map? ?? const <String, dynamic>{};
    final tokenInfo = m['token_info'] as Map? ?? const <String, dynamic>{};

    return AssetInfo(
      id: m['id'] is String ? m['id'] : '',
      interface: m['interface'] is String ? m['interface'] : '',
      name: meta['name'] is String ? meta['name'] : '',
      symbol: meta['symbol'] is String ? meta['symbol'] : '',
      balance: tokenInfo['balance']?.toString() ?? '',
      decimals: tokenInfo['decimals'] is num ? (tokenInfo['decimals'] as num).toInt() : 0,
      burnt: m['burnt'] == true,
      compressed: m['compression']?['compressed'] == true,
    );
  }

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

  factory TxInfo.fromMap(Map<String, dynamic> m) {
    return TxInfo(
      signature: m['signature'] is String ? m['signature'] : '',
      slot: m['slot'] is num ? (m['slot'] as num).toInt() : 0,
      err: m['err'],
      blockTime: (m['blockTime'] ?? m['block_time']) is num
          ? (m['blockTime'] ?? m['block_time'] as num).toInt()
          : 0,
      memo: m['memo'] is String ? m['memo'] : null,
    );
  }

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
