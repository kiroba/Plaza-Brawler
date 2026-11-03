// OmniMind opponents for the fight screens (spec 5.2), slimmed down to a thin delegate.
// Real: OmniMindClient (lib/net/omnimind_client.dart, daemon 8.26+ generate-asset) when Omni Node answers,
// otherwise the offline zodiac table (lib/npc/zodiac_offline.dart, source 'offline'). The fight AI itself is
// CpuBrain (lib/game/cpu_brain.dart); the old computeAction walk-and-punch AI is gone.
import '../game/fighter.dart';
import '../net/omni_node.dart';
import 'zodiac_offline.dart';

class OmniMindOpponents {
  const OmniMindOpponents();

  /// The opponent for [sign] (or the boss for 'ophiuchus') with this fight's [seed]. Never throws.
  Future<FighterDef> forSign(String sign, int seed) =>
      omniNode.opponent(sign, seed);

  /// A random offline pair for the attract loop (never touches the network).
  List<FighterDef> attractPair(int seed) {
    final a = zodiacSigns[seed.abs() % zodiacSigns.length];
    var b = zodiacSigns[(seed.abs() ~/ 12 + 5) % zodiacSigns.length];
    if (b == a)
      b = zodiacSigns[(zodiacSigns.indexOf(a) + 6) % zodiacSigns.length];
    return [offlineFighter(a)!, offlineFighter(b)!];
  }

  /// "OmniMind", "Offline", "LPE" or "Plaza" for the VS splash chip.
  static String chip(FighterDef f) {
    switch (f.source) {
      case 'omnimind':
        return 'OmniMind';
      case 'lpe':
        return 'LPE';
      case 'plaza':
        return 'Plaza';
      default:
        return 'Offline';
    }
  }
}

const omniMindOpponents = OmniMindOpponents();
