import 'dart:convert';
import 'dart:typed_data';

import 'package:solana/encoder.dart' show Instruction;
import 'package:solana/solana.dart';

import 'package:pipstats/base58.dart';
import 'package:pipstats/solscan_service.dart';
import 'package:pipstats/wallet_auth.dart';

/// The type of token being tipped.
enum TipToken { sol, skr }

/// A located SKR token account: its address, the token program that owns it,
/// and the balance read while locating it.
class SkrAccount {
  final String address;
  final TokenProgramType program;
  final int amount;

  const SkrAccount({
    required this.address,
    required this.program,
    required this.amount,
  });
}

/// Builds and submits SOL / SKR (Seeker) tips to the developer wallet.
///
/// The transaction is compiled here in Dart and handed to the native MWA layer
/// (`sendTip` on the `device_stats/usage` channel), which signs and submits it
/// through Seed Vault.
///
/// What goes over the channel is a full **transaction**: a signature count,
/// zeroed placeholder signature slots, then the message. The wallet fills the
/// signatures in. The channel argument is still named `message_bytes` for
/// compatibility with the native handler.
class TipService {
  const TipService._();
  static final TipService instance = TipService._();

  /// SKR token mint address.
  static const String skrMint = 'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3';

  /// SKR decimals, read from the mint on mainnet 2026-09-23.
  ///
  /// Used as a fallback only — [resolveDecimals] reads the live value, because
  /// a wrong figure here scales the transfer by a power of ten. This was 9 at
  /// first (copied from a reference snippet) and the resulting 1000x amount was
  /// caught on-device only because `transferChecked` verifies decimals against
  /// the mint; a plain `transfer` would have sent it.
  static const int skrDecimals = 6;

  /// SOL always has 9 decimals (1 SOL = 1e9 lamports).
  static const int solDecimals = 9;

  /// Minimum tip amounts, in base units (lamports / SKR atoms).
  static const int minSolLamports = 1000000; // 0.001 SOL
  static const int minSkrBaseUnits = 5000000; // 5 SKR at 6 decimals

  /// Minimum SKR tip in whole tokens, used to rescale the minimum when the
  /// mint reports decimals other than [skrDecimals].
  static const int minSkrWholeTokens = 5;

  /// The same minimums as display strings (used by the UI and error copy).
  static const String minSolDisplay = '0.001';
  static const String minSkrDisplay = '5';

  /// Developer wallet address for receiving tips.
  static const String devAddress =
      '5PpUJGRhM3FJN24mQD5wnKn6xSZLmA1ahPmouZvUFCHm';

  /// Rent-exempt minimum for an SPL token account (165 bytes). Charged to the
  /// sender when the recipient has no SKR account yet.
  static const int ataRentLamports = 2039280;

  /// Headroom kept aside for the transaction fee.
  static const int feeBufferLamports = 500000;

  // ---------------------------------------------------------------- amounts

  /// Converts a user-entered decimal string into integer base units.
  ///
  /// Returns null when the input is malformed, non-positive, or carries more
  /// precision than [decimals] allows — silently truncating a user's amount
  /// would send the wrong value. Parsing the string directly (rather than
  /// `(double * 10^decimals).toInt()`) avoids IEEE-754 loss: `0.07 * 1e9`
  /// evaluates to `69999999.99...`, which truncates to 69999999.
  static int? parseAmountToBaseUnits(String input, int decimals) {
    final s = input.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(s)) return null;

    final dot = s.indexOf('.');
    final whole = dot < 0 ? s : s.substring(0, dot);
    final fraction = dot < 0 ? '' : s.substring(dot + 1);
    if (whole.isEmpty && fraction.isEmpty) return null;
    if (fraction.length > decimals) return null;

    final digits = (whole.isEmpty ? '0' : whole) +
        fraction.padRight(decimals, '0');
    final value = BigInt.tryParse(digits);
    if (value == null || value <= BigInt.zero) return null;
    if (value > BigInt.from(0x7FFFFFFFFFFFFFFF)) return null;
    return value.toInt();
  }

  // ------------------------------------------------------- message building

  /// Associated token account address for [ownerAddress] and [mint].
  ///
  /// [tokenProgram] must match the program that owns the mint — legacy SPL
  /// Token and Token-2022 derive *different* ATAs for the same owner+mint.
  static Future<String> associatedTokenAddress(
    String ownerAddress, {
    String mint = skrMint,
    TokenProgramType tokenProgram = TokenProgramType.tokenProgram,
  }) async {
    final address = await findAssociatedTokenAddress(
      owner: Ed25519HDPublicKey.fromBase58(ownerAddress),
      mint: Ed25519HDPublicKey.fromBase58(mint),
      tokenProgramType: tokenProgram,
    );
    return address.toBase58();
  }


  /// Wraps a compiled legacy message in Solana's **transaction** wire format:
  /// a compact-u16 signature count, that many 64-byte signature slots left
  /// zeroed for the wallet to fill, then the message itself.
  ///
  /// MWA's `signAndSendTransactions` takes transactions, not bare messages.
  /// Sending a bare message makes the Seeker wallet refuse it with
  /// "Invalid transaction - the transaction from the site is not properly
  /// formed and can't be signed" (observed on device 2026-09-23).
  static List<int> _asUnsignedTransaction(List<int> message) {
    // Legacy message: the first header byte is numRequiredSignatures, and any
    // count below 128 encodes as a single compact-u16 byte.
    final signatureCount = message[0];
    return <int>[
      signatureCount,
      ...List<int>.filled(signatureCount * 64, 0),
      ...message,
    ];
  }

  /// Unsigned SOL transfer transaction bytes (pure, no I/O).
  static List<int> buildSolTipTransaction({
    required String ownerAddress,
    required String recipientAddress,
    required int lamports,
    required String blockhash,
  }) {
    final owner = Ed25519HDPublicKey.fromBase58(ownerAddress);
    final instruction = SystemInstruction.transfer(
      fundingAccount: owner,
      recipientAccount: Ed25519HDPublicKey.fromBase58(recipientAddress),
      lamports: lamports,
    );

    return _asUnsignedTransaction(
      Message.only(instruction)
          .compile(recentBlockhash: blockhash, feePayer: owner)
          .toByteArray()
          .toList(),
    );
  }

  /// Unsigned SKR transfer transaction bytes (no network I/O; the ATA
  /// derivation is an async but purely local PDA computation).
  ///
  /// When [createRecipientAccount] is true an idempotent
  /// `createAssociatedTokenAccount` is prepended, so the tip still lands if the
  /// recipient has no SKR account — and does not fail if one appears between
  /// the existence check and submission.
  static Future<List<int>> buildSkrTipTransaction({
    required String ownerAddress,
    required String senderTokenAccount,
    required String recipientOwnerAddress,
    required int rawAmount,
    required String blockhash,
    required bool createRecipientAccount,
    String mint = skrMint,
    int decimals = skrDecimals,
    TokenProgramType tokenProgram = TokenProgramType.tokenProgram,
  }) async {
    final owner = Ed25519HDPublicKey.fromBase58(ownerAddress);
    final source = Ed25519HDPublicKey.fromBase58(senderTokenAccount);
    final mintKey = Ed25519HDPublicKey.fromBase58(mint);
    final recipientOwner = Ed25519HDPublicKey.fromBase58(recipientOwnerAddress);
    final recipientAta = await findAssociatedTokenAddress(
      owner: recipientOwner,
      mint: mintKey,
      tokenProgramType: tokenProgram,
    );

    final instructions = <Instruction>[
      if (createRecipientAccount)
        AssociatedTokenAccountInstruction.createAccountIdempotent(
          funder: owner,
          address: recipientAta,
          owner: recipientOwner,
          mint: mintKey,
          tokenProgramId: tokenProgram.id,
        ),
      // transferChecked (not transfer): the program verifies mint and decimals
      // on-chain, so a wrong-decimals bug cannot silently move the wrong amount.
      TokenInstruction.transferChecked(
        amount: rawAmount,
        decimals: decimals,
        source: source,
        mint: mintKey,
        destination: recipientAta,
        owner: owner,
        tokenProgram: tokenProgram,
      ),
    ];

    return _asUnsignedTransaction(
      Message(instructions: instructions)
          .compile(recentBlockhash: blockhash, feePayer: owner)
          .toByteArray()
          .toList(),
    );
  }

  /// Decimals for [type], read from the mint for SKR so a stale constant can
  /// never rescale the amount. Falls back to [skrDecimals] when the mint is
  /// unreachable — `transferChecked` still rejects a mismatch on-chain.
  Future<int> resolveDecimals(TipToken type) async {
    if (type == TipToken.sol) return solDecimals;
    try {
      return await SolScanService.instance.getMintDecimals(skrMint) ??
          skrDecimals;
    } catch (_) {
      return skrDecimals;
    }
  }

  // ------------------------------------------------------------------ flow

  /// The sender's SKR token account, or null when the wallet holds no SKR.
  ///
  /// Legacy SPL Token and Token-2022 are queried separately so the owning
  /// program is known: the transfer instruction and the recipient's ATA must
  /// both target the same program as the mint.
  Future<SkrAccount?> findTokenAccount(String ownerAddress) async {
    for (final program in TokenProgramType.values) {
      final accounts = await SolScanService.instance.getTokenAccountsRaw(
        ownerAddress,
        programId: program.programId,
      );
      for (final acc in accounts) {
        final pubkey = acc['pubkey'];
        if (pubkey is! String) continue;
        final account = acc['account'];
        if (account is! Map) continue;
        final data = account['data'];
        final encoded = data is List && data.isNotEmpty ? data[0] : data;
        if (encoded is! String) continue;
        try {
          final info = parseTokenAccount(base64Decode(encoded));
          if (info != null && info.mint == skrMint) {
            return SkrAccount(
              address: pubkey,
              program: program,
              amount: info.amount,
            );
          }
        } catch (_) {
          continue;
        }
      }
    }
    return null;
  }

  /// Full flow: verify identity, build the transfer, sign + submit via MWA.
  /// Returns the base58 transaction signature.
  ///
  /// [amountText] is the raw user input, converted to base units without
  /// floating-point rounding.
  /// [ownerAddress] may be null: tipping does not require a wallet to be
  /// connected first, because signing already goes through Seed Vault. When it
  /// is null the wallet is authorised here and its address is adopted — and
  /// [onAuthorized] fires so the caller can remember it too.
  Future<String> sendTipFlow({
    String? ownerAddress,
    required String amountText,
    required TipToken type,
    void Function(WalletAuth auth)? onAuthorized,
  }) async {
    // 1. Establish which address we are spending from. When the caller named
    // one, check it against the session this app knows — a local check only,
    // since the wallet re-authorises during `transact`, which is what actually
    // gates signing. When it did not, whatever the wallet authorises is it, and
    // there is nothing to compare against.
    var owner = ownerAddress;
    final currentAuth = await WalletAuthService.instance.lastKnownWallet();
    if (currentAuth == null) {
      final auth = await WalletAuthService.instance.authorize();
      if (auth == null) throw Exception('AUTH_REQUIRED');
      if (owner != null && auth.address != owner) {
        throw Exception('IDENTITY_MISMATCH');
      }
      owner = auth.address;
      onAuthorized?.call(auth);
    } else if (owner == null) {
      owner = currentAuth.address;
    } else if (currentAuth.address != owner) {
      throw Exception('IDENTITY_MISMATCH');
    }
    final ownerAddr = owner;

    // 2. Resolve decimals from the mint, then parse and validate the amount.
    final decimals = await resolveDecimals(type);
    final rawAmount = parseAmountToBaseUnits(amountText, decimals);
    if (rawAmount == null) throw Exception('INVALID_AMOUNT');
    if (type == TipToken.sol) {
      if (rawAmount < minSolLamports) throw Exception('MIN_LIMIT_SOL');
      return _sendSolTip(ownerAddr, rawAmount);
    }
    final minSkr = minSkrWholeTokens * _pow10(decimals);
    if (rawAmount < minSkr) throw Exception('MIN_LIMIT_SKR');
    return _sendSkrTip(ownerAddr, rawAmount, decimals);
  }

  Future<String> _sendSolTip(String ownerAddress, int lamports) async {
    final balance =
        await SolScanService.instance.getBalanceLamports(ownerAddress);
    if (balance < lamports + feeBufferLamports) {
      throw Exception('INSUFFICIENT_SOL');
    }

    final blockhash = await SolScanService.instance.getLatestBlockhash();
    final transaction = buildSolTipTransaction(
      ownerAddress: ownerAddress,
      recipientAddress: devAddress,
      lamports: lamports,
      blockhash: blockhash,
    );

    return _submit(transaction);
  }

  static int _pow10(int exponent) {
    var v = 1;
    for (var i = 0; i < exponent; i++) {
      v *= 10;
    }
    return v;
  }

  Future<String> _sendSkrTip(
    String ownerAddress,
    int rawAmount,
    int decimals,
  ) async {
    // 1. The sender needs an SKR account holding enough tokens.
    final sender = await findTokenAccount(ownerAddress);
    if (sender == null) throw Exception('NO_SKR_ACCOUNT');
    if (sender.amount < rawAmount) throw Exception('INSUFFICIENT_SKR');

    // 2. The fee is always paid in SOL, even for a pure SKR transfer — and if
    // the recipient has no SKR account yet, the sender also funds its rent.
    final recipientAta = await associatedTokenAddress(
      devAddress,
      tokenProgram: sender.program,
    );
    final recipientExists =
        await SolScanService.instance.getAccountInfoBytes(recipientAta) != null;
    final requiredLamports =
        feeBufferLamports + (recipientExists ? 0 : ataRentLamports);
    final balance =
        await SolScanService.instance.getBalanceLamports(ownerAddress);
    if (balance < requiredLamports) throw Exception('INSUFFICIENT_SOL');

    final blockhash = await SolScanService.instance.getLatestBlockhash();
    final transaction = await buildSkrTipTransaction(
      ownerAddress: ownerAddress,
      senderTokenAccount: sender.address,
      recipientOwnerAddress: devAddress,
      rawAmount: rawAmount,
      blockhash: blockhash,
      createRecipientAccount: !recipientExists,
      tokenProgram: sender.program,
      decimals: decimals,
    );

    return _submit(transaction);
  }

  Future<String> _submit(List<int> transactionBytes) async {
    final response = await WalletAuthService.instance.sendTip(transactionBytes);
    // The native layer always returns a map on success; null means the user
    // dismissed the wallet or the channel method is unavailable.
    if (response == null) throw Exception('TIP_CANCELLED');

    final sigB64 = response['signature'] as String?;
    if (sigB64 == null || sigB64.isEmpty) {
      throw Exception('NO_SIGNATURE_RETURNED');
    }
    return base58Encode(Uint8List.fromList(base64.decode(sigB64)));
  }
}
