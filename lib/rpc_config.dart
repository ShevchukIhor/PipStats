/// Centralized Solana RPC configuration.
///
/// The Helius API key is supplied at build time via
/// `--dart-define=HELIUS_API_KEY=<key>` (or `--dart-define-from-file=defines.env`)
/// and is never hardcoded in source. Without a key we fall back to a free
/// public mainnet RPC — every feature still works, only rate limits differ.
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
///
/// Purely an RPC-endpoint preference now: token and NFT metadata are read
/// from Metaplex accounts on-chain, so no provider-specific API is required
/// and the app is fully functional on the free public RPC.
///
/// Note that a compile-time key is embedded in the APK in clear text and can
/// be extracted from any installed build — route it through a server-side
/// proxy if it must stay private.
bool get hasHeliusKey =>
    const String.fromEnvironment('HELIUS_API_KEY').isNotEmpty;

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
