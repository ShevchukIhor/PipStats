import 'dart:developer';

import 'package:flutter/services.dart';

import 'base58.dart';

/// Result of a wallet address resolution.
class WalletAuth {
  final String address; // base58 public key
  final String? accountLabel;

  const WalletAuth({required this.address, required this.accountLabel});
}

/// Wallet address resolution.
///
/// Supports Seed Vault authorization (Mobile Wallet Adapter) via the native
/// MethodChannel, and manual address entry (validated base58) as a fallback.
class WalletAuthService {
  const WalletAuthService._();
  static const WalletAuthService instance = WalletAuthService._();

  static const MethodChannel _channel = MethodChannel('device_stats/usage');

  /// Authorize via Seed Vault. Returns null if cancelled/unavailable.
  /// On failure, throws with the underlying PlatformException message so the
  /// UI can surface the real error instead of a generic "unavailable".
  Future<WalletAuth?> authorize() async {
    final map = await _channel.invokeMapMethod('authorizeWallet');
    return _fromMap(map);
  }

  /// The last wallet address this app saw, read from local storage.
  ///
  /// This is **not** a session check: no MWA auth token is validated, so a
  /// non-null result does not mean the wallet still authorises us. After the
  /// user revokes access in their wallet this keeps returning the old address
  /// until [deauthorize] is called. Named for what it does — the previous
  /// name `restore()` implied a silent reconnect that never happened.
  Future<WalletAuth?> lastKnownWallet() async {
    final map = await _channel.invokeMapMethod('restoreWallet');
    return _fromMap(map);
  }

  /// Revoke authorization and clear the persisted session.
  Future<void> deauthorize() async {
    try {
      await _channel.invokeMethod('deauthorize');
    } catch (e) {
      log('deauthorize error: $e');
    }
  }

  WalletAuth? _fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final bytes = map['pubkey_bytes'];
    final label = map['label'] as String?;
    if (bytes is! List) return null;
    final uint8 = Uint8List.fromList(
      bytes.map((e) => (e as num).toInt() & 0xFF).toList(),
    );
    if (uint8.length < 32) return null;
    return WalletAuth(address: base58Encode(uint8), accountLabel: label);
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

  /// Sign and submit a compiled transaction message via the native MWA layer.
  ///
  /// [messageBytes] is a compiled (unsigned) Solana message — the same shape
  /// the native `revokeDelegate` handler takes; the wallet appends signatures
  /// itself. Returns the native result map (`{signature: <base64>}`), or null
  /// when the user dismissed the wallet.
  Future<Map<Object?, Object?>?> sendTip(List<int> messageBytes) async {
    return await _channel.invokeMethod<Map<Object?, Object?>?>('sendTip', {
      'message_bytes': messageBytes,
    });
  }
}
