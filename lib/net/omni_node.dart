import 'dart:convert';
import 'package:http/http.dart' as http;

class OmniNodeClient {
  final String host = '127.0.0.1';
  final int daemonPort = 5000;
  final int lpePort = 5002;
  final String bearerToken = 'OMNI_CONTAINER_BEARER_TOKEN';
  bool isConnected = false;
  String userPubkey = '0x_USER_STARGATE_ED25519_PUBKEY_DEFAULT';
  String previousHash = '0x0000000000000000000000000000000000000000000000000000000000000000';

  String get daemonUrl => 'http://$host:$daemonPort';
  String get lpeUrl => 'http://$host:$lpePort';

  Future<bool> checkConnection() async {
    try {
      final res = await http.get(
        Uri.parse('$daemonUrl/api/v1/health'),
        headers: {'Authorization': 'Bearer $bearerToken'},
      ).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        isConnected = true;
        userPubkey = data['node_id'] ?? userPubkey;
        return true;
      }
    } catch (e) {
      print('[OmniNode] Local daemon not reachable: $e');
    }
    isConnected = false;
    return false;
  }

  Future<Map<String, dynamic>> fetchUserLPE() async {
    try {
      final res = await http.get(
        Uri.parse('$lpeUrl/api/v1/lpe/persona'),
        headers: {'Authorization': 'Bearer $bearerToken'},
      ).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      print('[OmniNode] LPE service unreachable: $e');
    }
    return {
      'persona_id': 'user_lpe_fallback',
      'archetype': 'ZODIAC_ARIES',
      'aura_hex': '#FF3300',
      'palette': ['#FF3300', '#FF8800', '#FFD700'],
      'stats': {'str': 16, 'dex': 14, 'int': 10, 'spr': 12}
    };
  }

  Future<bool> dispatchEvent(String action, Map<String, dynamic> payload) async {
    final eventEnvelope = {
      'action': action,
      'author_pubkey': userPubkey,
      'payload': payload,
      'previous_hash': previousHash,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    print('[OmniNode] Dispatching Signed Event ($action): $eventEnvelope');

    if (isConnected) {
      try {
        final res = await http.post(
          Uri.parse('$daemonUrl/api/events/append'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode(eventEnvelope),
        ).timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          final resData = jsonDecode(res.body);
          previousHash = resData['event_id'] ?? previousHash;
          return true;
        }
      } catch (e) {
        print('[OmniNode] Error sending event to daemon: $e');
      }
    }
    return false;
  }
}

final omniNode = OmniNodeClient();
