import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pipstats/solscan_service.dart';

/// Golden tests for [parseTokenAccount] against **real mainnet accounts**.
///
/// Each fixture is the verbatim base64 `account.data` returned by
/// `getAccountInfo(..., encoding: "base64")`, and every expectation below is
/// what the Solana node itself reported for the same account through
/// `encoding: "jsonParsed"`. The node's own decoder is the oracle, so these
/// tests cannot drift into agreeing with a bug in our decoder — which is
/// exactly how the previous synthetic fixtures let a wrong layout pass.
///
/// Captured 2026-09-23 from `solana-rpc.publicnode.com` (mainnet-beta).
///
/// Each pair of encodings was read at the **same slot** — the wrapped-SOL
/// account below is actively traded, and a base64 snapshot taken minutes
/// apart from its `jsonParsed` reading disagreed on `amount` by ~1.6 SOL.
/// When refreshing a fixture, fetch both encodings in one batched request and
/// check that `result.context.slot` matches.
void main() {
  group('parseTokenAccount — real mainnet accounts', () {
    test('plain SKR account (no delegate, no close authority)', () {
      // 13i3jdgEMt1xAfdEurCv4aMmZHQCsHga8wCuPFucgvzK
      const data =
          'BnxaPgX+QUcSp6Lq/kK+dhC82Qy/VxYndYNzy4rQ2KTXAeNnANywVipqubkF1iItyBnqv3DidSTYyfTDfjzClcuGFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final bytes = base64Decode(data);
      expect(bytes.length, 165);

      final info = parseTokenAccount(bytes)!;
      expect(info.mint, 'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3');
      expect(info.owner, 'FUJKrQhxWYu4z59G6JGVfZstjQKi1fY1BZNwoekgs9vL');
      expect(info.amount, 1345227);
      // Node reports state "initialized". The old decoder returned 0 here for
      // every real account, because it read `state` out of the delegate tag.
      expect(info.state, 1);
      expect(info.delegate, isNull);
      expect(info.hasDelegate, isFalse);
      expect(info.delegatedAmount, 0);
      expect(info.closeAuthority, isNull);
      expect(info.isNative, isFalse);
      expect(info.nativeAmount, 0);
    });

    test('wrapped SOL account (is_native carries the rent reserve)', () {
      // 1nTCkNNPrBTWMB3vPLrixJdarn2UypE6vjE49AnEisj
      const data =
          'BpuIV/6rgYT7aH9jRhjANdrEOdwa6ztVmKDwAAAAAAEhGsY9F0LpetZgnqPxAz+aGAUXNxr5SKZ2EQ5/Lk+CjLQxLILqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQEAAAA4thYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final bytes = base64Decode(data);
      expect(bytes.length, 165);

      final info = parseTokenAccount(bytes)!;
      expect(info.mint, 'So11111111111111111111111111111111111111112');
      expect(info.owner, '3EE8jokQEqz7g2MfxjojHJCd7W5izUjDePATiBBGP571');
      expect(info.amount, 1007206281652);
      expect(info.state, 1);
      expect(info.isNative, isTrue);
      // Node reports rentExemptReserve = 1488440.
      expect(info.nativeAmount, 1488440);
      // is_native sits between `state` and `delegated_amount`; the old decoder
      // read them in the opposite order and corrupted both.
      expect(info.delegatedAmount, 0);
      expect(info.delegate, isNull);
    });

    test('account with an active delegate', () {
      // 4iYd4j6qpDs9zaGiFX33zXp3xWSJg4zeKRjZFnAYGzXK
      const data =
          'BnWhzzR5T83H1gLersnn3noiJQvjMeMyGY4+dyHD5wRxS70yqy/HWFJ0EL/ERJdN7kQJ3ft4XfbALXiK7zC8FKhRAAAAAAAAAQAAAJoTxyNXBeWNJsZ4wjuHhqJ3bhX2nmiD/Lp8KBnvC0uMAQAAAAAAAAAAAAAAAKhRAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final bytes = base64Decode(data);
      expect(bytes.length, 165);

      final info = parseTokenAccount(bytes)!;
      expect(info.mint, 'SDUsgfSZaDhhZ76U3ZgvtFiXsfnHbf2VrzYxjBZ5YbM');
      expect(info.owner, '8dG489uxonsv9sVhd9UPMg1ojbdxptpRsQCkd6pg3doy');
      expect(info.amount, 20904);
      expect(info.hasDelegate, isTrue);
      // This is the headline regression: the old decoder read the delegate
      // from offset 73 instead of 76, reporting a plausible-looking but wrong
      // spender address in the security scanner.
      expect(info.delegate, 'BNTH5DWDPWsHsSQVscqJVe2GQKnQcAmPt4BLRPMGPfHu');
      expect(info.delegatedAmount, 20904);
      expect(info.state, 1);
      expect(info.isNative, isFalse);
      expect(info.closeAuthority, isNull);
    });
  });
}
