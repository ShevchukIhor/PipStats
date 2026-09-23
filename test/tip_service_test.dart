import 'package:flutter_test/flutter_test.dart';
import 'package:solana/solana.dart' show TokenProgramType;

import 'package:pipstats/tip_service.dart';

void main() {
  // Valid base58 pubkeys reused as stand-ins; the builders only care that the
  // input decodes to 32 bytes.
  const owner = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  const recipient = '5PpUJGRhM3FJN24mQD5wnKn6xSZLmA1ahPmouZvUFCHm';
  const recipient2 = 'So11111111111111111111111111111111111111112';
  const senderAta = '11111111111111111111111111111111';
  const blockhash = 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k';

  group('TipService.parseAmountToBaseUnits', () {
    test('converts whole and fractional amounts exactly', () {
      expect(TipService.parseAmountToBaseUnits('1', 9), 1000000000);
      expect(TipService.parseAmountToBaseUnits('0.001', 9), 1000000);
      expect(TipService.parseAmountToBaseUnits('5', 9), 5000000000);
      expect(TipService.parseAmountToBaseUnits('12.345', 9), 12345000000);
      expect(TipService.parseAmountToBaseUnits('0.000000001', 9), 1);
    });

    test('keeps precision that double arithmetic would lose', () {
      // `(8.2 * pow(10, 9)).toInt()` evaluates to 8199999999 in IEEE-754
      // double math — one atom short. String parsing is exact.
      expect(TipService.parseAmountToBaseUnits('8.2', 9), 8200000000);
      expect(TipService.parseAmountToBaseUnits('0.07', 9), 70000000);
    });

    test('accepts a comma as the decimal separator', () {
      expect(TipService.parseAmountToBaseUnits('0,5', 9), 500000000);
    });

    test('rejects more precision than the token has decimals', () {
      expect(TipService.parseAmountToBaseUnits('0.0000000001', 9), isNull);
      expect(TipService.parseAmountToBaseUnits('1.5', 0), isNull);
    });

    test('rejects malformed, empty, negative and zero amounts', () {
      for (final bad in ['', '   ', 'abc', '-1', '1.2.3', '0', '0.0', '.']) {
        expect(
          TipService.parseAmountToBaseUnits(bad, 9),
          isNull,
          reason: 'should reject "$bad"',
        );
      }
    });
  });

  group('TipService.buildSolTipTransaction', () {
    test('emits transaction wire format, not a bare message', () {
      final bytes = TipService.buildSolTipTransaction(
        ownerAddress: owner,
        recipientAddress: recipient,
        lamports: 1000000,
        blockhash: blockhash,
      );
      // MWA signAndSendTransactions takes a transaction: compact-u16 signature
      // count, then that many zeroed 64-byte slots, then the message. A bare
      // message is rejected by the wallet as "Invalid transaction".
      expect(bytes.first, 1, reason: 'one signature slot (the tipping wallet)');
      expect(
        bytes.sublist(1, 65),
        everyElement(0),
        reason: 'placeholder signature must be zeroed for the wallet to fill',
      );
      final message = bytes.sublist(65);
      expect(
        message.first,
        1,
        reason: 'message header still leads with numRequiredSignatures',
      );
      expect(message.length, greaterThan(32));
    });

    test('is deterministic for identical inputs', () {
      List<int> build() => TipService.buildSolTipTransaction(
        ownerAddress: owner,
        recipientAddress: recipient,
        lamports: 1000000,
        blockhash: blockhash,
      );
      expect(build(), build());
    });

    test('a different amount yields different bytes', () {
      final a = TipService.buildSolTipTransaction(
        ownerAddress: owner,
        recipientAddress: recipient,
        lamports: 1000000,
        blockhash: blockhash,
      );
      final b = TipService.buildSolTipTransaction(
        ownerAddress: owner,
        recipientAddress: recipient,
        lamports: 2000000,
        blockhash: blockhash,
      );
      expect(a, isNot(equals(b)));
    });

    test('a different recipient yields different bytes', () {
      final a = TipService.buildSolTipTransaction(
        ownerAddress: owner,
        recipientAddress: recipient,
        lamports: 1000000,
        blockhash: blockhash,
      );
      final b = TipService.buildSolTipTransaction(
        ownerAddress: owner,
        recipientAddress: recipient2,
        lamports: 1000000,
        blockhash: blockhash,
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects a malformed owner address', () {
      expect(
        () => TipService.buildSolTipTransaction(
          ownerAddress: 'short',
          recipientAddress: recipient,
          lamports: 1000000,
          blockhash: blockhash,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TipService.associatedTokenAddress', () {
    test('derives a valid, deterministic address', () async {
      final a = await TipService.associatedTokenAddress(recipient);
      final b = await TipService.associatedTokenAddress(recipient);
      expect(a, b);
      expect(a.length, inInclusiveRange(32, 44));
    });

    test('differs per owner and per mint', () async {
      final a = await TipService.associatedTokenAddress(recipient);
      final b = await TipService.associatedTokenAddress(recipient2);
      expect(a, isNot(equals(b)));

      final c = await TipService.associatedTokenAddress(
        recipient,
        mint: recipient2,
      );
      expect(a, isNot(equals(c)));
    });

    test('Token-2022 derives a different ATA than legacy SPL Token', () async {
      final legacy = await TipService.associatedTokenAddress(recipient);
      final token2022 = await TipService.associatedTokenAddress(
        recipient,
        tokenProgram: TokenProgramType.token2022Program,
      );
      expect(
        legacy,
        isNot(equals(token2022)),
        reason: 'sending to the legacy ATA of a Token-2022 mint loses the tip',
      );
    });
  });

  group('TipService.buildSkrTipTransaction', () {
    Future<List<int>> build({bool createRecipientAccount = false}) =>
        TipService.buildSkrTipTransaction(
          ownerAddress: owner,
          senderTokenAccount: senderAta,
          recipientOwnerAddress: recipient,
          rawAmount: 5000000000,
          blockhash: blockhash,
          createRecipientAccount: createRecipientAccount,
        );

    test('emits transaction wire format, not a bare message', () async {
      final bytes = await build();
      expect(bytes.first, 1);
      expect(bytes.sublist(1, 65), everyElement(0));
      expect(bytes.sublist(65).first, 1);
    });

    test('is deterministic for identical inputs', () async {
      expect(await build(), await build());
    });

    test('creating the recipient account adds an instruction', () async {
      final without = await build();
      final with_ = await build(createRecipientAccount: true);
      expect(with_, isNot(equals(without)));
      expect(
        with_.length,
        greaterThan(without.length),
        reason: 'the ATA-create instruction and its accounts must be present',
      );
    });

    test('a different amount yields different bytes', () async {
      final a = await build();
      final b = await TipService.buildSkrTipTransaction(
        ownerAddress: owner,
        senderTokenAccount: senderAta,
        recipientOwnerAddress: recipient,
        rawAmount: 6000000000,
        blockhash: blockhash,
        createRecipientAccount: false,
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects a malformed sender token account', () async {
      expect(
        () => TipService.buildSkrTipTransaction(
          ownerAddress: owner,
          senderTokenAccount: 'short',
          recipientOwnerAddress: recipient,
          rawAmount: 5000000000,
          blockhash: blockhash,
          createRecipientAccount: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TipService minimum amounts', () {
    test('minimums are expressed in base units', () {
      expect(
        TipService.minSolLamports,
        TipService.parseAmountToBaseUnits('0.001', TipService.solDecimals),
      );
      expect(
        TipService.minSkrBaseUnits,
        TipService.parseAmountToBaseUnits('5', TipService.skrDecimals),
        reason: 'the SKR minimum must track the mint decimals',
      );
      expect(
        TipService.minSkrBaseUnits,
        TipService.minSkrWholeTokens * 1000000,
      );
    });

    test('SKR decimals match the mainnet mint', () {
      // Read from the SKR mint on 2026-09-23. A wrong value here multiplies
      // the transferred amount by a power of ten; 9 (the original guess)
      // would have sent 1000x.
      expect(TipService.skrDecimals, 6);
    });
  });
}
