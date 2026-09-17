/// Centralized Solana RPC configuration.
///
/// The Helius API key is supplied at build time via
/// `--dart-define=HELIUS_API_KEY=<key>` (or `--dart-define-from-file=defines.env`)
/// and is never hardcoded in source. Without a key we fall back to a free
/// public mainnet RPC (rate-limited, and **no DAS** — see [hasHeliusKey]).
class MissingRpcKey implements Exception {
  @override
  String toString() =>
      'HELIUS_API_KEY is missing. Build with '
      '--dart-define=HELIUS_API_KEY=<key> (see README).';
}

/// Free public mainnet RPC (no key required).
const String publicRpcUrl = 'https://api.mainnet-beta.solana.com';

const String _heliusBase = 'https://mainnet.helius-rpc.com/?api-key=';

/// Test/override hook: when non-null, [rpcUrl] returns this verbatim,
/// bypassing the compile-time API-key lookup.
String? rpcOverride;

/// True when a Helius key was supplied at build time (compile-time define).
/// Helius is required for DAS (`getAssetsByOwner`) — token/NFT metadata.
bool get hasHeliusKey =>
    const String.fromEnvironment('HELIUS_API_KEY').isNotEmpty;

/// True when Digital Asset Standard (DAS) lookups are available, i.e. running
/// against Helius (or an override/testing endpoint). On the public fallback
/// RPC, `getAssetsByOwner` is unsupported.
bool get dasAvailable => rpcOverride != null || hasHeliusKey;

/// Builds the RPC endpoint.
///
/// Returns the Helius endpoint when a key is available (from [apiKey] or the
/// compile-time `HELIUS_API_KEY` define), otherwise the free public RPC.
String rpcUrl({String? apiKey}) {
  final o = rpcOverride;
  if (o != null) return o;
  final key = apiKey ?? const String.fromEnvironment('HELIUS_API_KEY');
  if (key.isNotEmpty) return '$_heliusBase$key';
  return publicRpcUrl;
}
