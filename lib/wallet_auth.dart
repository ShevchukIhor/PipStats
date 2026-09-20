import 'dart:convert';
import 'dart:developer';
import 'dart:math' show pow;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'base58.dart';

/// Result of a wallet address resolution.
class WalletAuth {
  final String address; // base58 public key
  final String? accountLabel;

  const WalletAuth({required this.address, required this.accountLabel});
}

/// Solana network cluster pinned for the MWA authorize request.
///
/// The Seeker wallet defaults its Mobile Wallet Adapter association to
/// **devnet** unless the dApp requests a cluster; a mainnet SKR transfer must
/// be authorised on mainnet or the wallet rejects it as "Invalid Transaction".
const String kMainnetCluster = 'mainnet';

/// Wallet gateway built on a **single, persistent** `solana_mobile_client`
/// session.
///
/// MWA hands out exactly one working local association per app at a time.
/// Opening a *second* association for a later sign (as separate native
/// `transact` calls did) fails on the Seeker wallet ("Local association was
/// cancelled before connected" / "Unable to connect to websocket server").
/// So we hold ONE scene/client from connect and reuse it for the tip.
class WalletAuthService {
  WalletAuthService._();
  static final WalletAuthService instance = WalletAuthService._();

  static const MethodChannel _channel = MethodChannel('device_stats/usage');

  LocalAssociationScenario? _scenario;
  MobileWalletAdapterClient? _client;
  String? _authToken;
  String? _pubkey;
  String? _label;

  WalletAuth? get current {
    final p = _pubkey;
    return p == null ? null : WalletAuth(address: p, accountLabel: _label);
  }

  /// Open (or reuse) the persistent MWA session and authorise it on mainnet.
  Future<WalletAuth?> authorize() async {
    final existing = current;
    if (existing != null) return existing;

    final session = await LocalAssociationScenario.create();
    await session.startActivityForResult(null);
    final client = await session.start();

    late final AuthorizationResult? auth;
    try {
      auth = await client.authorize(
        identityUri: Uri.parse('https://pipstats.pages.dev/'),
        iconUri: Uri.parse('https://pipstats.pages.dev/assets/logo-icon.png'),
        identityName: 'PipStats',
        cluster: kMainnetCluster,
      );
    } catch (e) {
      await session.close();
      rethrow;
    }
    if (auth == null) {
      await session.close();
      return null;
    }

    _scenario = session;
    _client = client;
    _authToken = auth.authToken;
    _pubkey = base58Encode(auth.publicKey);
    _label = auth.accountLabel;

    // Persist so restore()/balance still work after process death.
    try {
      await _channel.invokeMethod('persistWallet', {
        'pubkey_bytes': auth.publicKey.toList(),
        'label': auth.accountLabel,
      });
    } catch (_) {}

    return current;
  }

  /// Restore a previously-persisted address without opening a session.
  Future<WalletAuth?> restore() async {
    final existing = current;
    if (existing != null) return existing;
    try {
      final map = await _channel.invokeMapMethod('restoreWallet');
      if (map == null) return null;
      final bytes = map['pubkey_bytes'];
      if (bytes is! List) return null;
      final uint8 = Uint8List.fromList(
        bytes.map((e) => (e as num).toInt() & 0xFF).toList(),
      );
      if (uint8.length < 32) return null;
      _pubkey = base58Encode(uint8);
      _label = map['label'] as String?;
      return current;
    } catch (e) {
      log('restore error: $e');
      return null;
    }
  }

  /// Close the persistent session and clear persisted state.
  Future<void> deauthorize() async {
    try {
      final t = _authToken;
      final c = _client;
      if (t != null && c != null) await c.deauthorize(authToken: t);
    } catch (_) {}
    try {
      await _scenario?.close();
    } catch (_) {}
    _client = null;
    _scenario = null;
    _authToken = null;
    _pubkey = null;
    _label = null;
    try {
      await _channel.invokeMethod('clearWallet');
      await _channel.invokeMethod('deauthorize');
    } catch (_) {}
  }

  // ---- SKR tip over the persistent session ----

  Future<String> _getBlockhash() async {
    final resp = await http
        .post(
          Uri.parse('https://api.mainnet-beta.solana.com'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'getLatestBlockhash',
            'params': [{'commitment': 'finalized'}],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw Exception('RPC HTTP ${resp.statusCode}');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception('RPC error: ${json['error']}');
    return (json['result'] as Map<String, dynamic>)['value']['blockhash'] as String;
  }

  Future<Uint8List> _buildTransfer({
    required String ownerAddress,
    required double amountSkr,
    required String blockhash,
  }) async {
    const mint = 'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3';
    const decimals = 6;
    const recipient = '5PpUJGRhM3FJN24mQD5wnKn6xSZLmA1ahPmouZvUFCHm';

    final owner = Ed25519HDPublicKey.fromBase58(ownerAddress);
    final mintKey = Ed25519HDPublicKey.fromBase58(mint);
    final senderAta = await findAssociatedTokenAddress(owner: owner, mint: mintKey);
    final devPubkey = Ed25519HDPublicKey.fromBase58(recipient);
    final recipientAta = await findAssociatedTokenAddress(owner: devPubkey, mint: mintKey);

    final amountRaw = (amountSkr * pow(10, decimals)).round();

    final transferIx = TokenInstruction.transfer(
      source: senderAta,
      destination: recipientAta,
      owner: owner,
      amount: amountRaw,
      signers: [owner],
    );

    final message = Message(instructions: [transferIx]);
    final compiled = message.compile(recentBlockhash: blockhash, feePayer: owner);
    return Uint8List.fromList(compiled.toByteArray().toList());
  }

  /// Send an SKR tip over the already-open persistent session (no second
  /// local association). Returns the transaction signature (base58).
  Future<String> sendTip({required double amountSkr, required String senderAddress}) async {
    if (_client == null) {
      final auth = await authorize();
      if (auth == null) throw Exception('Wallet not connected');
    }

    final blockhash = await _getBlockhash();
    final txBytes = await _buildTransfer(
      ownerAddress: senderAddress,
      amountSkr: amountSkr,
      blockhash: blockhash,
    );
    debugPrint('TIP: BASE64=${base64Encode(txBytes)}');

    final result = await _client!.signAndSendTransactions(transactions: [txBytes]);
    if (result.signatures.isEmpty) throw Exception('Sign-and-send returned no signature');
    return base58Encode(result.signatures.first);
  }

  /// True if this wallet address looks like a base58 pubkey (32..44 chars).
  static bool isValidAddress(String addr) {
    final s = addr.trim();
    if (s.isEmpty) return false;
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    for (final c in s.runes) {
      final ch = String.fromCharCode(c);
      if (!alphabet.contains(ch)) return false;
    }
    return s.length >= 32 && s.length <= 44;
  }

  /// True if the input looks like a `.skr` domain (e.g. `alice.skr`).
  static bool isSkrDomain(String input) {
    final s = input.trim().toLowerCase();
    return s.length > 4 && s.endsWith('.skr') && !s.contains(' ');
  }

  /// Resolve a manually-entered address into a WalletAuth.
  WalletAuth? fromManual(String addr) {
    final s = addr.trim();
    if (!isValidAddress(s)) return null;
    return WalletAuth(address: s, accountLabel: null);
  }
}