import 'dart:math';

// OmniMind opponent generation is NOT wired yet: Omni Node (daemon v8.23.0) has no
// generate-asset endpoint, so the opponent is always this offline persona (`source: offline`)
// and the UI says so. The fight AI below (computeAction) runs on the phone and is unchanged.
class OmniMindNPCHook {
  Map<String, dynamic>? currentOpponent;

  Future<Map<String, dynamic>> generateOpponentNPC({String sign = 'Scorpio'}) async {
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
      },
      'source': 'offline',
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
