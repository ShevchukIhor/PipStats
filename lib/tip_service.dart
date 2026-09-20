import 'dart:convert';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'base58.dart';

/// Solana network cluster pinned for the MWA authorize request.
///
/// The Seeker wallet defaults its Mobile Wallet Adapter association to
/// **devnet** unless the dApp explicitly requests a cluster. A mainnet SKR
/// transfer must be authorised on `mainnet` or the wallet rejects the
/// (mainnet) transaction as "Invalid Transaction".
const String kMainnetCluster = 'mainnet';

/// Sends an SKR tip via the Solana Mobile Wallet Adapter (Seed Vault),
/// authorising the MWA session on **mainnet**. Uses the [solana_mobile_client]
/// plugin, whose `authorize(cluster:)` lets the dApp pin the network — the
/// low-level clientlib we used before cannot set it and always defaulted to
/// devnet (hence the recurring "Invalid Transaction").
///
/// The recipient token account already exists on mainnet
/// (8aQTbb4TRSvwk7KHSgz6ivqEFDyX77yDTgTQ65TV3CFc), so we only sign a plain
/// SPL transfer (no ATA creation needed).
class TipService {
  TipService({
    this.rpcUrl = 'https://api.mainnet-beta.solana.com',
    this.mint = 'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3',
    this.decimals = 6,
  });

  final String rpcUrl;
  final String mint;
  final int decimals;
  static const String recipient = '5PpUJGRhM3FJN24mQD5wnKn6xSZLmA1ahPmouZvUFCHm';

  Future<String> _getBlockhash() async {
    final resp = await http
        .post(
          Uri.parse(rpcUrl),
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

  /// Full flow: open a local MWA session, authorise it on mainnet, sign and
  /// send the SKR transfer, close the session. Returns the tx signature (base58).
  Future<String> sendTip({required double amountSkr, required String senderAddress}) async {
    final blockhash = await _getBlockhash();
    final txBytes = await _buildTransfer(
      ownerAddress: senderAddress,
      amountSkr: amountSkr,
      blockhash: blockhash,
    );
    debugPrint('TIP: BASE64=${base64Encode(txBytes)}');

    final session = await LocalAssociationScenario.create();
    try {
      // Launch the wallet sheet FIRST, then wait for the WS connection.
      await session.startActivityForResult(null);
      final client = await session.start();

      final auth = await client.authorize(
        identityUri: Uri.parse('https://pipstats.pages.dev/'),
        iconUri: Uri.parse('https://pipstats.pages.dev/assets/logo-icon.png'),
        identityName: 'PipStats',
        cluster: kMainnetCluster,
      );
      if (auth == null) {
        throw Exception('Wallet authorization was declined (expected mainnet cluster)');
      }

      final authPubkey = base58Encode(auth.publicKey);
      if (authPubkey != senderAddress) {
        throw Exception('Wallet selected $authPubkey, expected $senderAddress');
      }

      final result = await client.signAndSendTransactions(transactions: [txBytes]);
      if (result.signatures.isEmpty) {
        throw Exception('Sign-and-send returned no signature');
      }
      return base58Encode(result.signatures.first);
    } finally {
      await session.close();
    }
  }
}