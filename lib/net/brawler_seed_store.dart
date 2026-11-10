// Plaza Brawler's identity seed store: the per-person seed in
// flutter_secure_storage (Android Keystore-encrypted).
//
// Plaza Brawler originally never set StargateIdentity.seedStore, so it fell
// back to Omni-Core-UI's SQLite store (not Keystore-encrypted). The storage
// key matches LPE's ('lpe_ed25519_seed_v1'), but be precise about what that
// means: Android sandboxes every app's storage, so this app can NEVER read
// LPE's copy - the shared name only keeps the convention in one place. The
// seed itself crosses apps by the identity transfer code (see
// identity_transfer.dart): LPE exports it, this app imports it in Settings.
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
