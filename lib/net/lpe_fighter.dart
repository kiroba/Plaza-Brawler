// The player's fighter from their Live Persona Engine profile (spec 5.1). Pure Dart.
// Real: LpeClient.profile() (GET :5000/api/lpe/profile, daemon 8.25+) -> FighterDef with source 'lpe',
// handle and aura tier from the profile. The daemon's LPE profile has NO zodiac field today (handle, avatar
// text, cosmetics, aura{tier: PARAGON|CITIZEN|DISTRUSTED|SLASHED, ...}), so the sign comes from an explicit
// sign/zodiac field if a future node adds one, else from the sign the player picked (saved on the phone).
import '../game/fighter.dart';
import '../npc/zodiac_offline.dart';
import 'lpe_client.dart';

const String lpeNoProfile = 'No profile yet: offline fighter';

/// Sign named by the profile itself ('sign', 'zodiac', 'zodiac_sign' or an 'archetype' like
/// 'ZODIAC_ARIES'), or null. Never guesses from free text.
String? signFromLpeProfile(Map<String, dynamic> profile) {
  for (final k in const ['sign', 'zodiac', 'zodiac_sign', 'archetype']) {
    final v = profile[k];
    if (v is! String) continue;
    var s = v.trim().toLowerCase();
    if (s.startsWith('zodiac_')) s = s.substring(7);
    if (zodiacTable.containsKey(s)) return s;
  }
  return null;
}

/// The player's fighter from an LPE profile, or null when there's no profile or no sign to build on
/// (then the UI asks the player to pick one and calls again with [chosenSign]).
/// Stats are the sign's base stats (the LPE has none); identity and colour come from the profile.
FighterDef? fighterFromLpe(
  Map<String, dynamic>? profile, {
  String? chosenSign,
}) {
  if (profile == null) return null;
  try {
    final sign =
        signFromLpeProfile(profile) ?? chosenSign?.trim().toLowerCase();
    final base = sign == null ? null : offlineFighter(sign);
    if (base == null) return null;
    final aura = profile['aura'] is Map ? profile['aura'] as Map : const {};
    final handle = (profile['handle_display'] ?? profile['handle'] ?? '')
        .toString()
        .trim();
    final tier = (aura['tier'] ?? '').toString().trim();
    final auraArgb = hexToArgb(
      aura['aura_color_hex']?.toString(),
      fallback: base.primary,
    );
    final pubkey = (profile['pubkey'] ?? '').toString();
    final layers = [
      for (final l in base.layers)
        l.layer == 'aura'
            ? FighterLayer(
                layer: l.layer,
                assetId: l.assetId,
                z: l.z,
                tint: auraArgb,
                opacity: l.opacity,
              )
            : l,
    ];
    return base.copyWith(
      id: 'lpe_${pubkey.length >= 12 ? pubkey.substring(0, 12) : pubkey}',
      name: handle.isEmpty ? base.name : handle,
      source: 'lpe',
      primary: auraArgb,
      handle: handle.isEmpty ? null : handle,
      auraTier: tier.isEmpty ? null : tier,
      layers: layers,
    );
  } catch (_) {
    return null;
  }
}

/// Reads this key's profile and builds the fighter; null on any failure. Never throws.
Future<FighterDef?> lpeFighter(
  LpeClient lpe,
  String pubkey, {
  String? chosenSign,
}) async {
  try {
    return fighterFromLpe(await lpe.profile(pubkey), chosenSign: chosenSign);
  } catch (_) {
    return null;
  }
}

/// Settings line for "Your fighter (Live Persona Engine)" (spec 5.1).
/// [profile] is what LpeClient.profile returned; [nodeConnected] is the node-health check result.
/// LpeClient.profile returns null both for "node has no LPE API" and "no profile for this key" (both are
/// HTTP 404 on the daemon), so a reachable node with no profile reads as [lpeNoProfile].
String lpeStatusLine(
  Map<String, dynamic>? profile, {
  required bool nodeConnected,
}) {
  if (profile != null) {
    final aura = profile['aura'] is Map ? profile['aura'] as Map : const {};
    final handle = (profile['handle_display'] ?? profile['handle'] ?? '?')
        .toString();
    final tier = (aura['tier'] ?? '?').toString();
    return 'Connected: $handle (aura tier $tier)';
  }
  return nodeConnected ? lpeNoProfile : needsNode825;
}
