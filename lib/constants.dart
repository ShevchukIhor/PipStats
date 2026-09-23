/// Constants for Solana programs and configuration.
class SolanaConstants {
  static const String systemProgram = '11111111111111111111111111111111';
  static const String tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const String token2022Program = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
  static const String solMint = 'So11111111111111111111111111111111111111112';

  /// Serialized size of an SPL Token account. Token-2022 appends extensions
  /// after this base, so buffers may be longer — never shorter.
  /// See `TokenAccountLayout` in `solscan_service.dart` for the field offsets.
  static const int tokenAccountLength = 165;

  /// Standard timeout duration for RPC requests.
  static const Duration rpcTimeout = Duration(seconds: 20);

  /// Cache duration for prices and assets.
  static const Duration cacheDuration = Duration(seconds: 30);

  /// Backoff duration for retries.
  static const Duration retryBackoff = Duration(milliseconds: 500);

  // Private constructor to prevent instantiation.
  SolanaConstants._();
}
