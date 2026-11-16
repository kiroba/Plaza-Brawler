// Figure packs in the Brawler (pack-loader slice, Nov 13). Pure Dart.
//
// Real: the two OmniStudio reference packs are bundled unpacked under
// assets/packs/<mod_id>/ (byte-identical copies of Phaser-Studio main; the
// .omnimod ZIP stays the distribution format between repos and nodes). This
// file parses a pack manifest (omnimod 1.0.0, category 'cosmetic_skin') into
// a FighterSpriteBinding and attaches it to the DEFAULT PLAYER TEMPLATES —
// the starter Halos a new player begins from and customizes in LPE. The
// packs are never roster fighters and carry no names, stats or personalities
// of their own; identity comes from the player's LPE persona at runtime.
//
// Loading is injected ([loadText]) so this file needs no Flutter bindings
// and stays unit-testable; the UI layer passes rootBundle's loader. Every
// failure mode (missing pack, malformed manifest, missing sprite) resolves
// to null and the fighter stays painted — select never blocks, a match
// never crashes.
import 'dart:convert';

import '../game/fighter.dart';

/// The bundled default-Halo packs, in pipeline order.
const List<String> defaultPackIds = [
  'omnimod.base.reference-male-01',
  'omnimod.base.reference-female-01',
];

/// The pack an LPE fighter wears when the profile says nothing figure-like.
const String defaultPackId = 'omnimod.base.reference-male-01';

/// Where a bundled pack lives in the app's asset bundle.
String packManifestAsset(String packId) => 'assets/packs/$packId/manifest.json';

String _packDir(String packId) => 'assets/packs/$packId';

/// The sprite binding a pack manifest describes, or null when the manifest
/// is not a usable figure pack (wrong shape, not a cosmetic_skin, or the
/// portrait / three-quarter sprites are absent). Never throws.
FighterSpriteBinding? bindingFromManifest(
  Map<String, dynamic> manifest, {
  required String packId,
}) {
  try {
    if (manifest['category'] != 'cosmetic_skin') return null;
    final assets = manifest['assets'];
    if (assets is! Map) return null;
    final sheets = assets['spritesheets'];
    if (sheets is! List) return null;
    String? fileFor(String profile) {
      for (final s in sheets) {
        if (s is Map && s['profile'] == profile) {
          final f = s['file'];
          if (f is String && f.isNotEmpty) return f;
        }
      }
      return null;
    }

    final portrait = fileFor('portrait');
    final body = fileFor('three_quarter');
    if (portrait == null || body == null) return null;
    final dir = _packDir(packId);
    return FighterSpriteBinding(
      portraitAsset: '$dir/$portrait',
      bodyAsset: '$dir/$body',
      packId: packId,
    );
  } catch (_) {
    return null;
  }
}

/// Decodes manifest JSON text into a binding; null on any malformation.
FighterSpriteBinding? bindingFromManifestJson(
  String jsonText, {
  required String packId,
}) {
  try {
    final m = jsonDecode(jsonText);
    if (m is! Map<String, dynamic>) return null;
    return bindingFromManifest(m, packId: packId);
  } catch (_) {
    return null;
  }
}

/// Loads one bundled pack's binding via [loadText] (an asset-text loader,
/// e.g. rootBundle.loadString). Null when the pack can't be read or parsed.
Future<FighterSpriteBinding?> loadPackBinding(
  Future<String> Function(String asset) loadText,
  String packId,
) async {
  try {
    return bindingFromManifestJson(
      await loadText(packManifestAsset(packId)),
      packId: packId,
    );
  } catch (_) {
    return null;
  }
}

/// Which bundled pack an LPE profile points at, or null when it says nothing
/// figure-like. Reads only explicit fields — a 'figure' / 'template' /
/// 'pack' / 'mod_id' naming a bundled pack, a 'gender' / 'sex' of
/// 'female' | 'male', or a cosmetics entry naming a pack or figure. Like
/// signFromLpeProfile, it never guesses from free text (the avatar line).
String? packIdFromProfile(Map<String, dynamic> profile) {
  for (final k in const ['figure', 'template', 'pack', 'mod_id']) {
    final v = profile[k];
    if (v is String && defaultPackIds.contains(v.trim())) return v.trim();
  }
  for (final k in const ['gender', 'sex']) {
    final v = profile[k];
    if (v is String) {
      final g = v.trim().toLowerCase();
      if (g == 'female') return 'omnimod.base.reference-female-01';
      if (g == 'male') return 'omnimod.base.reference-male-01';
    }
  }
  final cosmetics = profile['cosmetics'];
  if (cosmetics is List) {
    for (final c in cosmetics) {
      if (c is! String) continue;
      if (defaultPackIds.contains(c)) return c;
      final cl = c.toLowerCase();
      if (cl == 'figure_female' || cl == 'female_figure') {
        return 'omnimod.base.reference-female-01';
      }
      if (cl == 'figure_male' || cl == 'male_figure') {
        return 'omnimod.base.reference-male-01';
      }
    }
  }
  return null;
}

/// [def] wearing [binding] (a null binding leaves the def untouched).
FighterDef withPackSprite(FighterDef def, FighterSpriteBinding? binding) =>
    binding == null ? def : def.copyWith(sprite: binding);
