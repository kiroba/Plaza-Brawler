// Plaza Brawler's identity seed store: the per-person seed in
// flutter_secure_storage (Android Keystore-encrypted), under the SAME
// storage key the LPE app uses, so on one phone the Brawler, LPE and the
// node all act as ONE person: one Ed25519 key, one Halo.
//
// Plaza Brawler originally never set StargateIdentity.seedStore, so it fell
// back to Omni-Core-UI's shared SQLite store and minted its own key - the
// node then had no LPE profile for the Brawler's key, and the player fought
// as the offline persona even with a Halo saved in LPE. The key string must
// stay byte-identical to LPE's SecureStorageSeedStore._key
// (kiroba/LPE lib/lpe_identity.dart); if it ever changes, change both.
//
// Migration, same pattern as LPE/KickBack: a seed an earlier build kept in
// the SQLite store is copied here on first read and the SQLite copy deleted,
// so an existing Brawler identity survives the move.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

class BrawlerSeedStore implements IdentitySeedStore {
  static const String _key = 'lpe_ed25519_seed_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<List<int>?> read() async {
    final v = await _storage.read(key: _key);
    if (v != null) return base64Decode(v);

    final legacy = SqliteSeedStore();
    final old = await legacy.read();
    if (old == null) return null;
    await write(old);
    final check = await _storage.read(key: _key);
    if (check != null && check == base64Encode(old)) {
      await legacy.delete();
    }
    return old;
  }

  @override
  Future<void> write(List<int> seed) =>
      _storage.write(key: _key, value: base64Encode(seed));
}
