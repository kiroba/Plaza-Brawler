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
// What is NOT wired yet (labelled in the UI, never faked):
//   - Sharing game events with the node. The hub has no game/match endpoint, and
//     /api/events/append is the shared chain that relays to every peer, so per-hit fight events
//     don't belong there. Events stay local until a game endpoint exists.
//   - The player's Live Persona Engine (LPE) needs Omni Node 8.25+ (GET /api/lpe/profile and
//     /api/lpe/plaza, see lib/net/lpe_client.dart). With an older node, no node, or no LPE profile
//     for this key yet, the offline persona is used and labelled "Needs Omni Node 8.25+".
//   - OmniMind opponent generation (see lib/npc/omnimind.dart).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

import 'lpe_client.dart';

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
  }

  Future<void> saveToken(String value) async {
    _token = value.trim();
    await _store.write(key: _tokenKey, value: _token);
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
        return v == null ? 'Connected to Omni Node' : 'Connected to Omni Node (v$v)';
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
  LpeClient get lpe => LpeClient(host: host, ipcPort: ipcPort, token: _token.isEmpty ? null : _token);

  /// True when the last [fetchUserLPE] got this player's profile from Omni Node.
  bool userLpeFromNode = false;

  /// True when the last [fetchPlazaOpponent] found a real avatar on Omni Node.
  bool opponentFromPlaza = false;

  static const Map<String, dynamic> offlinePersona = {
    'persona_id': 'user_lpe_offline',
    'archetype': 'ZODIAC_ARIES',
    'aura_hex': '#FF3300',
    'palette': ['#FF3300', '#FF8800', '#FFD700'],
    'stats': {'str': 16, 'dex': 14, 'int': 10, 'spr': 12},
    'source': 'offline',
  };

  /// The player's Live Persona Engine profile from Omni Node (daemon 8.25+) when the node answers
  /// and has a profile for this key; otherwise the offline persona (`source: offline`).
  Future<Map<String, dynamic>> fetchUserLPE() async {
    userLpeFromNode = false;
    if (isConnected && userPubkey.isNotEmpty) {
      final p = await lpe.profile(userPubkey);
      if (p != null) {
        userLpeFromNode = true;
        return personaFromLpe(p, offlinePersona);
      }
    }
    return Map<String, dynamic>.from(offlinePersona);
  }

  /// A real opponent from the node's plaza (another known avatar), built on [fallback]'s fight
  /// behaviour; [fallback] itself when the node has no LPE API or nobody else is in the plaza.
  Future<Map<String, dynamic>> fetchPlazaOpponent(Map<String, dynamic> fallback) async {
    opponentFromPlaza = false;
    if (!isConnected) return fallback;
    final avatars = await lpe.plaza(viewer: userPubkey);
    final pick = avatars == null ? null : pickOpponent(avatars, userPubkey);
    if (pick == null) return fallback;
    opponentFromPlaza = true;
    return personaFromLpe(pick, fallback);
  }

  /// One line for the boot screen about where both fighters came from.
  String get fightersWords {
    final p1 = userLpeFromNode ? 'your LPE profile' : 'offline persona (LPE: $needsNode825)';
    final p2 = opponentFromPlaza ? 'plaza avatar' : 'offline persona (OmniMind: $notWiredYet)';
    return 'Fighter: $p1\nOpponent: $p2';
  }

  /// Signs the game event with this install's Ed25519 key and stores it on this phone.
  /// It is NOT sent to Omni Node (no game endpoint yet). Returns true when stored.
  Future<bool> dispatchEvent(String action, Map<String, dynamic> payload) async {
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
