import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:solana/solana.dart';

import 'base58.dart';
import 'solscan_service.dart';

/// Resolves `.skr` domains (AllDomains / ALT Name Service, Solana) to their
/// owner wallet address. Forward-only, ported from `@onsol/tldparser`.
class SkrResolver {
  const SkrResolver._();
  static const SkrResolver instance = SkrResolver._();

  static const String ansProgram =
      'ALTNSZ46uaAUU7XUV6awvdorLGqAsPwa9shm7h4uP2FK';
  static const String tldHouseProgram =
      'TLDHkysf5pCnKsVA4gXpNvmy7psXLPEu4LAdDJthT9S';
  static const String nameHouseProgram =
      'NH3uX6FtVE2fNREAioP7hm5RaozotZxeL6khU1EHx51';
  static const String originTld = 'ANS';
  static const String _hashPrefix = 'ALT Name Service';
  static const int _nameRecordOwnerOffset = 40;
  static const int _nftRecordTagOffset = 8;
  static const int _nftRecordMintOffset = 41;

  static final Uint8List _zeros32 = Uint8List(32);

  /// Derives the ANS origin name account. Used as a derivation smoke test and
  /// must always equal `3mX9b4AZaQehNoQGfckVcmgmA6bkBoFcbLj9RMmMyNcU`.
  static Future<String> originNameAccountKey() =>
      _pda([hashName(originTld), _zeros32, _zeros32], ansProgram);

  /// Hashes a name label using the ALT Name Service prefix (sha256 -> 32 bytes).
  static Uint8List hashName(String name) {
    return Uint8List.fromList(
      crypto.sha256.convert(utf8.encode(_hashPrefix + name)).bytes,
    );
  }

  /// Parses the owner (base58) out of a raw name-account buffer, or null when
  /// the account is too short or the owner is the zero pubkey.
  static String? parseNameRecordOwner(Uint8List data) {
    if (data.length < _nameRecordOwnerOffset + 32) return null;
    final owner = base58Encode(
      Uint8List.fromList(
        data.sublist(_nameRecordOwnerOffset, _nameRecordOwnerOffset + 32),
      ),
    );
    if (_isZeroPubkey(owner)) return null;
    return owner;
  }

  /// Resolve a domain like `alice.skr` to the owner's base58 address,
  /// handling both unwrapped and wrapped (NFT) domains. Returns null when the
  /// domain is malformed, missing, or resolution fails.
  Future<String?> resolve(String domain) async {
    final name = domain.trim().toLowerCase();
    final cleaned = name.endsWith('.')
        ? name.substring(0, name.length - 1)
        : name;
    final parts = cleaned.split('.');
    if (parts.length != 2 || parts[1] != 'skr' || parts[0].isEmpty) {
      return null;
    }
    final sub = parts[0];
    const tld = '.skr';

    // Origin name account (the ANS root).
    final originKey = await _pda([
      hashName(originTld),
      _zeros32,
      _zeros32,
    ], ansProgram);

    // Parent name account for the ".skr" TLD.
    final parentKey = await _pda([
      hashName(tld),
      _zeros32,
      _bytes(originKey),
    ], ansProgram);

    // The domain's name account.
    final domainKey = await _pda([
      hashName(sub),
      _zeros32,
      _bytes(parentKey),
    ], ansProgram);

    // Resolve the name record's owner.
    final data = await SolScanService.instance.getAccountInfoBytes(domainKey);
    if (data == null) return null;
    final owner = parseNameRecordOwner(data);
    if (owner == null) return null;

    // If the record is owned by its NFT-record PDA, resolve the actual holder.
    final tldHouse = await _pda([
      utf8.encode('tld_house'),
      utf8.encode(tld),
    ], tldHouseProgram);
    final nameHouse = await _pda([
      utf8.encode('name_house'),
      _bytes(tldHouse),
    ], nameHouseProgram);
    final nftRecord = await _pda([
      utf8.encode('nft_record'),
      _bytes(nameHouse),
      _bytes(domainKey),
    ], nameHouseProgram);

    if (owner == nftRecord) {
      return await _resolveNftOwner(nftRecord);
    }
    return owner;
  }

  Future<String?> _resolveNftOwner(String nftRecord) async {
    final data = await SolScanService.instance.getAccountInfoBytes(nftRecord);
    if (data == null || data.length < _nftRecordMintOffset + 32) return null;
    // tag: 0 = Uninitialized, 1 = ActiveRecord, 2 = InactiveRecord
    if (data[_nftRecordTagOffset] != 1) return null;
    final mint = base58Encode(
      Uint8List.fromList(
        data.sublist(_nftRecordMintOffset, _nftRecordMintOffset + 32),
      ),
    );
    return await SolScanService.instance.getTokenLargestOwner(mint);
  }

  static Future<String> _pda(List<List<int>> seeds, String programId) async {
    final p = await Ed25519HDPublicKey.findProgramAddress(
      seeds: seeds,
      programId: Ed25519HDPublicKey.fromBase58(programId),
    );
    return base58Encode(Uint8List.fromList(p.bytes));
  }

  static List<int> _bytes(String base58Pubkey) =>
      Ed25519HDPublicKey.fromBase58(base58Pubkey).bytes;

  static bool _isZeroPubkey(String base58) =>
      base58.split('').every((c) => c == '1');
}
