// Plaza Brawler's link to Omni Node, built on the shared Omni-Core-UI clients.
//
// What is real here:
//   - Connection check: OmniHubClient.connection() -> GET :9100/api/v1/telemetry/node-health
//     (served by daemon v8.23.0, see Omni-Daemon Admin/docs/API_REFERENCE.md). The Omni Node
//     token from "Omni Node > Connect apps" is sent as "Authorization: Bearer <token>", which the
//     daemon accepts on loopback since v8.20.0 (the Android node app requires it).
//   - Identity: StargateIdentity, this install's Ed25519 key.
//   - Game events: signed with that key and hash-chained by LocalEventStore, kept on this phone.
//
//   - Live Persona Engine (daemon 8.25+): the player's fighter from GET :5000/api/lpe/profile
//     (lib/net/lpe_fighter.dart) and Quick Fight's "Plaza challenger" from /api/lpe/plaza.
//   - OmniMind opponents (daemon 8.26+): GET :5000/api/v1/omnimind/generate-asset
//     (lib/net/omnimind_client.dart); offline zodiac fighters when the node doesn't answer.
//
// What is NOT wired yet (labelled in the UI, never faked):
//   - Sharing match results with the node. The hub has no game/match endpoint yet, and
//     /api/events/append is the shared chain that relays to every peer, so fight events don't
//     belong there. Summaries stay on this phone (lib/net/match_share.dart) until one exists.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

import '../game/fighter.dart';
import '../npc/zodiac_offline.dart';
import 'lpe_client.dart';
import 'lpe_fighter.dart';
import 'omnimind_client.dart';

const FlutterSecureStorage _store = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Label used everywhere a feature is a stand-in rather than a real service.
const String notWiredYet = 'Not wired yet';

class OmniNodeClient {
  /// Omni Node on this phone. Cleartext HTTP is only allowed to loopback (network_security_config).
  static const String host = '127.0.0.1';
  static const int telemetryPort = 9100;
  static const int ipcPort = 5000;
  static const String _tokenKey = 'plaza_brawler_node_token_v1';

  String _token = '';
  HubConnection? _last;
  StargateIdentity? _identity;
  final LocalEventStore _events = LocalEventStore();

  /// The Omni Node token pasted in Settings (empty = none yet).
  String get token => _token;

  /// Result of the last [checkConnection], or null before the first check.
  HubConnection? get lastConnection => _last;

  bool get isConnected => _last?.connected ?? false;

  /// This install's Ed25519 public key (64 hex), or '' before [loadIdentity].
  String get userPubkey => _identity?.pubkeyHex ?? '';

  String get shortId => _identity?.shortId ?? '';

  OmniHubClient get hub => OmniHubClient(
    host: host,
    telemetryPort: telemetryPort,
    ipcPort: ipcPort,
    token: _token.isEmpty ? null : _token,
  );

  /// Reads the saved token. Never throws.
  Future<void> loadSettings() async {
    try {
      _token = (await _store.read(key: _tokenKey)) ?? '';
    } catch (_) {
      _token = '';
    }
    _rebuildClients();
  }

  Future<void> saveToken(String value) async {
    _token = value.trim();
    _rebuildClients();
    try {
      await _store.write(key: _tokenKey, value: _token);
    } catch (_) {}
  }

  void _rebuildClients() {
    final ok = omniMind.lastOk;
    omniMind = OmniMindClient(
      host: host,
      ipcPort: ipcPort,
      token: _token.isEmpty ? null : _token,
    )..lastOk = ok;
  }

  /// Loads (or creates on first launch) this install's Ed25519 identity. Never throws.
  Future<StargateIdentity?> loadIdentity() async {
    try {
      _identity ??= await StargateIdentity.load();
    } catch (_) {}
    return _identity;
  }

  /// Real health check against node-health on :9100. Never throws.
  Future<HubConnection> checkConnection() async {
    _last = await hub.connection();
    return _last!;
  }

  /// One line for the status dot: what the last check found, in plain words.
  String get statusWords {
    final c = _last;
    if (c == null) return 'Checking Omni Node...';
    switch (c.state) {
      case HubConnectionState.connected:
        final v = c.status.version;
        return v == null
            ? 'Connected to Omni Node'
            : 'Connected to Omni Node (v$v)';
      case HubConnectionState.unauthorized:
        return _token.isEmpty
            ? 'Omni Node needs a token. Paste it in Settings.'
            : 'Omni Node refused the token. Paste it again from Connect apps.';
      case HubConnectionState.forbidden:
        return 'Omni Node refused this app (HTTP 403).';
      case HubConnectionState.unreachable:
        return 'Omni Node is not running on this phone.';
      case HubConnectionState.error:
        return 'Omni Node problem: ${c.detail ?? 'unexpected reply'}';
    }
  }

  /// LPE reads on Omni Node's :5000, with the same token as [hub].
  LpeClient get lpe => LpeClient(
    host: host,
    ipcPort: ipcPort,
    token: _token.isEmpty ? null : _token,
  );

  /// OmniMind opponents on Omni Node's :5000 (daemon 8.26+), with the same token as [hub].
  OmniMindClient omniMind = OmniMindClient(host: host, ipcPort: ipcPort);

  /// This player's LPE profile from the last [refreshLpe] (null: no node, node < 8.25, or no profile).
  Map<String, dynamic>? lpeProfile;

  /// Reads this key's LPE profile. Never throws.
  Future<Map<String, dynamic>?> refreshLpe() async {
    lpeProfile = null;
    if (isConnected && userPubkey.isNotEmpty) {
      try {
        lpeProfile = await lpe.profile(userPubkey);
      } catch (_) {
        lpeProfile = null;
      }
    }
    return lpeProfile;
  }

  /// Asks OmniMind for one opponent so Settings and the title chips show its real state. Never throws.
  Future<bool> probeOmniMind() async {
    if (!isConnected) {
      omniMind.lastOk = false;
      return false;
    }
    return await omniMind.generateNpc('aries', 0) != null;
  }

  /// The sign the LPE profile names itself (no daemon sends one today), or null.
  String? get lpeSign =>
      lpeProfile == null ? null : signFromLpeProfile(lpeProfile!);

  /// The player's fighter from the LPE profile with [chosenSign] (the sign picked on this phone), or the
  /// offline fighter for [chosenSign] when there is no profile. Null only when there is no sign at all.
  FighterDef? playerFighter(String? chosenSign) {
    final f = fighterFromLpe(lpeProfile, chosenSign: chosenSign);
    if (f != null) return f;
    return chosenSign == null ? null : offlineFighter(chosenSign);
  }

  /// An opponent for [sign] + [seed]: OmniMind's when the node answers, else offline. Never throws.
  Future<FighterDef> opponent(String sign, int seed) async {
    if (sign == 'ophiuchus') return bossFighter();
    if (!isConnected) {
      omniMind.lastOk = false;
      return offlineFighter(sign) ?? bossFighter();
    }
    return await omniMind.npcFighter(sign, seed) ??
        offlineFighter(sign) ??
        bossFighter();
  }

  /// A real avatar from the node's plaza as a CPU-driven fighter (Quick Fight's "Plaza challenger"), or
  /// null when the node has no LPE API or nobody else is there. The plaza has no signs, so the fighting
  /// style comes from a sign picked by the avatar's key (stable for that avatar).
  Future<FighterDef?> plazaChallenger() async {
    if (!isConnected) return null;
    try {
      final avatars = await lpe.plaza(viewer: userPubkey);
      final pick = avatars == null ? null : pickOpponent(avatars, userPubkey);
      if (pick == null) return null;
      final pk = (pick['pubkey'] ?? '').toString();
      var h = 0;
      for (final c in pk.codeUnits) {
        h = (h * 31 + c) & 0x7fffffff;
      }
      final f = fighterFromLpe(
        pick,
        chosenSign: zodiacSigns[h % zodiacSigns.length],
      );
      return f?.copyWith(source: 'plaza');
    } catch (_) {
      return null;
    }
  }

  // Status helpers (spec 5.1, 5.2, 5.4): real states only.
  bool get lpeConnected => lpeProfile != null;
  bool get omniMindConnected => omniMind.lastOk == true;
  String get lpeStatus => lpeStatusLine(lpeProfile, nodeConnected: isConnected);
  String get omniMindStatus => omniMind.statusLine();

  /// One line for the boot screen about where both fighters come from.
  String get fightersWords {
    final p1 = lpeConnected
        ? 'your LPE profile'
        : 'offline fighter ($lpeStatus)';
    final p2 = omniMindConnected
        ? 'OmniMind on Omni Node'
        : 'offline zodiac fighters';
    return 'Fighter: $p1\nOpponents: $p2';
  }

  /// Signs the game event with this install's Ed25519 key and stores it on this phone.
  /// It is NOT sent to Omni Node (no game endpoint yet). Returns true when stored.
  Future<bool> dispatchEvent(
    String action,
    Map<String, dynamic> payload,
  ) async {
    try {
      await loadIdentity();
      await _events.append(action, {'app': 'plaza-brawler', ...payload});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// How many fight events are stored (signed) on this phone. Never throws.
  Future<int> localEventCount() async {
    try {
      return (await _events.recent(limit: 100000))
          .where((e) => e.action.startsWith('FIGHTER_'))
          .length;
    } catch (_) {
      return 0;
    }
  }
}

final omniNode = OmniNodeClient();
