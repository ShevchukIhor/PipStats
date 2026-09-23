import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';

import 'base58.dart';
import 'rpc_config.dart';

/// Builds and submits a Solana "Revoke" transaction, clearing a token account's
/// delegate (neutralizing the approved spender).
class RevokeService {
  const RevokeService._();
  static const RevokeService instance = RevokeService._();

  static const MethodChannel _channel = MethodChannel('device_stats/usage');

  /// Fetch the recent blockhash string from RPC.
  Future<String> _getBlockhash() async {
    const maxAttempts = 3;
    for (var attempt = 0; ; attempt++) {
      final resp = await http
          .post(
            Uri.parse(rpcUrl()),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'getLatestBlockhash',
              'params': [
                {'commitment': 'finalized'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 429 && attempt < maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        continue;
      }
      if (resp.statusCode != 200) {
        throw Exception('RPC HTTP ${resp.statusCode}');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['error'] != null) {
        throw Exception('RPC error: ${json['error']}');
      }
      final value =
          (json['result'] as Map<String, dynamic>)['value']
              as Map<String, dynamic>;
      return value['blockhash'] as String;
    }
  }

  /// Build the unsigned revoke transaction bytes (pure, no I/O) for a token
  /// account delegating its spender back to nothing. The MWA layer signs and
  /// sends these bytes via Seed Vault.
  ///
  /// Returns transaction wire format (signature count + placeholder slots +
  /// message), which is what MWA `signAndSendTransactions` accepts.
  static List<int> buildRevokeMessage({
    required String ownerAddress,
    required String tokenAccount,
    required String blockhash,
  }) {
    final owner = Ed25519HDPublicKey.fromBase58(ownerAddress);
    final source = Ed25519HDPublicKey.fromBase58(tokenAccount);

    final instruction = TokenInstruction.revoke(
      source: source,
      sourceOwner: owner,
      signers: [owner],
    );

    final message = Message.only(instruction);
    final compiled = message.compile(
      recentBlockhash: blockhash,
      feePayer: owner,
    );

    // MWA `signAndSendTransactions` expects a serialized TRANSACTION: a
    // compact-u16 signature count, that many zeroed 64-byte signature slots,
    // then the message. The wallet fills the signatures in.
    //
    // An earlier comment here claimed the opposite — that a bare message was
    // required and placeholders broke signing. That was a wrong conclusion
    // drawn from the "Invalid Transaction" failures which actually came from
    // the adapter defaulting to the devnet chain (fixed in WalletConnect.kt).
    // Sending a bare message makes the Seeker wallet reject it outright with
    // "Invalid transaction - not properly formed" (observed on device).
    final messageBytes = compiled.toByteArray().toList();
    // legacy header: first byte is numRequiredSignatures
    final signatureCount = messageBytes[0];
    return <int>[
      signatureCount,
      ...List<int>.filled(signatureCount * 64, 0),
      ...messageBytes,
    ];
  }

  /// Build the unsigned revoke transaction message bytes and submit it to the
  /// native MWA layer for signing + sending via Seed Vault.
  /// Returns the first transaction signature (base58) on success.
  Future<String> revoke({
    required String ownerAddress,
    required String tokenAccount,
  }) async {
    final blockhash = await _getBlockhash();

    final txBytes = buildRevokeMessage(
      ownerAddress: ownerAddress,
      tokenAccount: tokenAccount,
      blockhash: blockhash,
    );

    final response = await _channel.invokeMethod<Map>('revokeDelegate', {
      'message_bytes': txBytes,
    });

    if (response == null) {
      throw Exception('REVOKE CANCELLED OR UNAVAILABLE');
    }
    final sigB64 = response['signature'] as String?;
    if (sigB64 == null || sigB64.isEmpty) {
      throw Exception('NO SIGNATURE RETURNED');
    }
    final sigBytes = base64.decode(sigB64);
    return base58Encode(Uint8List.fromList(sigBytes));
  }
}
