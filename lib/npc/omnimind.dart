import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class OmniMindNPCHook {
  final String host = '127.0.0.1';
  final int daemonPort = 5000;
  Map<String, dynamic>? currentOpponent;

  String get daemonUrl => 'http://$host:$daemonPort';

  Future<Map<String, dynamic>> generateOpponentNPC({String sign = 'Scorpio'}) async {
    try {
      final res = await http.get(
        Uri.parse('$daemonUrl/api/v1/omnimind/generate-asset?type=zodiac_npc&sign=$sign'),
      ).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        currentOpponent = jsonDecode(res.body);
        return currentOpponent!;
      }
    } catch (e) {
      print('[OmniMind] Daemon asset generator unavailable: $e');
    }

    currentOpponent = {
      'persona_id': 'npc_lpe_scorpio_offline',
      'archetype': 'ZODIAC_SCORPIO',
      'name': 'Shadow Alchemist (Scorpio)',
      'zodiac_sign': 'Scorpio',
      'element': 'Water',
      'aura_hex': '#4B0082',
      'palette': ['#00BFFF', '#1E90FF', '#00008B'],
      'behavior_weights': {
        'aggression': 0.3,
        'intuition': 0.95,
        'curiosity': 0.6,
        'stamina': 0.4,
      }
    };
    return currentOpponent!;
  }

  Map<String, dynamic> computeAction(double npcX, double playerX, double npcHp) {
    if (currentOpponent == null) return {'move': 'IDLE', 'attack': false};

    final distance = (npcX - playerX).abs();
    final weights = currentOpponent!['behavior_weights'] ?? {'aggression': 0.5, 'intuition': 0.5};

    if (distance > 70) {
      final dir = playerX < npcX ? -1.0 : 1.0;
      return {'move': 'WALK', 'dir': dir, 'attack': false};
    } else {
      final aggression = (weights['aggression'] as num).toDouble();
      final intuition = (weights['intuition'] as num).toDouble();
      final attackChance = aggression + (intuition * 0.2);
      final shouldAttack = Random().nextDouble() < attackChance;
      return {'move': 'ATTACK', 'attack': shouldAttack, 'attackType': 'PUNCH'};
    }
  }
}

final omniMind = OmniMindNPCHook();
