// Figure-pack loader (pure Dart): manifest parsing, profile pack choice,
// build-time integrity of the two bundled packs against their manifests,
// and the LPE attach path. The packs are default player templates — never
// roster fighters.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:plaza_brawler/net/lpe_fighter.dart';
import 'package:plaza_brawler/net/pack_fighter.dart';

Map<String, dynamic> _manifest({
  String category = 'cosmetic_skin',
  List<Object?>? sheets,
}) => {
  'manifest_version': '1.0.0',
  'mod_id': 'omnimod.base.reference-male-01',
  'category': category,
  'assets': {
    'spritesheets':
        sheets ??
        const [
          {
            'id': 'sprite_portrait',
            'file': 'sprites/sprite_portrait_128.png',
            'frame_px': 128,
            'profile': 'portrait',
            'sha256': 'x',
          },
          {
            'id': 'sprite_three_quarter',
            'file': 'sprites/sprite_three_quarter_128.png',
            'frame_px': 128,
            'profile': 'three_quarter',
            'sha256': 'y',
          },
        ],
  },
};

void main() {
  group('bindingFromManifest', () {
    test('a valid pack manifest binds portrait + three-quarter assets', () {
      final b = bindingFromManifest(
        _manifest(),
        packId: 'omnimod.base.reference-male-01',
      )!;
      expect(
        b.portraitAsset,
        'assets/packs/omnimod.base.reference-male-01/sprites/sprite_portrait_128.png',
      );
      expect(
        b.bodyAsset,
        'assets/packs/omnimod.base.reference-male-01/sprites/sprite_three_quarter_128.png',
      );
      expect(b.packId, 'omnimod.base.reference-male-01');
    });

    test('a non-cosmetic category does not bind', () {
      expect(
        bindingFromManifest(
          _manifest(category: 'prop'),
          packId: 'omnimod.base.reference-male-01',
        ),
        isNull,
      );
    });

    test('a missing three-quarter sprite does not bind', () {
      final m = _manifest(
        sheets: const [
          {'profile': 'portrait', 'file': 'sprites/sprite_portrait_128.png'},
        ],
      );
      expect(
        bindingFromManifest(m, packId: 'omnimod.base.reference-male-01'),
        isNull,
      );
    });

    test('malformed shapes return null, never throw', () {
      expect(bindingFromManifest({}, packId: 'x'), isNull);
      expect(
        bindingFromManifest({'category': 'cosmetic_skin'}, packId: 'x'),
        isNull,
      );
      expect(
        bindingFromManifest({
          'category': 'cosmetic_skin',
          'assets': {'spritesheets': 'nope'},
        }, packId: 'x'),
        isNull,
      );
      expect(bindingFromManifestJson('{not json', packId: 'x'), isNull);
      expect(bindingFromManifestJson('[1,2]', packId: 'x'), isNull);
    });
  });

  group('loadPackBinding', () {
    test('reads the manifest through the injected loader', () async {
      final b = await loadPackBinding(
        (asset) async {
          expect(
            asset,
            'assets/packs/omnimod.base.reference-female-01/manifest.json',
          );
          return jsonEncode(_manifest());
        },
        'omnimod.base.reference-female-01',
      );
      expect(b, isNotNull);
      expect(b!.packId, 'omnimod.base.reference-female-01');
    });

    test('a loader failure resolves to null (painted fallback)', () async {
      final b = await loadPackBinding(
        (asset) async => throw StateError('missing'),
        'omnimod.base.reference-male-01',
      );
      expect(b, isNull);
    });
  });

  group('packIdFromProfile', () {
    test('says nothing when the profile says nothing figure-like', () {
      expect(packIdFromProfile({}), isNull);
      // The avatar free text is never guessed from.
      expect(packIdFromProfile({'avatar': 'a woman in a red hoodie'}), isNull);
      expect(packIdFromProfile({'handle': 'female_fox'}), isNull);
    });

    test('explicit fields win', () {
      expect(
        packIdFromProfile({'gender': 'female'}),
        'omnimod.base.reference-female-01',
      );
      expect(
        packIdFromProfile({'gender': 'Male'}),
        'omnimod.base.reference-male-01',
      );
      expect(
        packIdFromProfile({'figure': 'omnimod.base.reference-female-01'}),
        'omnimod.base.reference-female-01',
      );
      expect(
        packIdFromProfile({'figure': 'omnimod.someone.elses-pack'}),
        isNull,
      );
    });

    test('cosmetics can name the figure', () {
      expect(
        packIdFromProfile({
          'cosmetics': ['figure_female'],
        }),
        'omnimod.base.reference-female-01',
      );
      expect(
        packIdFromProfile({
          'cosmetics': ['omnimod.base.reference-male-01'],
        }),
        'omnimod.base.reference-male-01',
      );
    });
  });

  group('the bundled packs (build-time integrity)', () {
    for (final packId in defaultPackIds) {
      test('$packId: manifest binds and every sprite matches its sha256', () {
        final dir = Directory('assets/packs/$packId');
        final manifest =
            jsonDecode(File('${dir.path}/manifest.json').readAsStringSync())
                as Map<String, dynamic>;
        final binding = bindingFromManifest(manifest, packId: packId);
        expect(binding, isNotNull);
        final sheets =
            (manifest['assets'] as Map)['spritesheets'] as List<dynamic>;
        expect(sheets.length, 4);
        for (final s in sheets) {
          final file = File('${dir.path}/${s['file']}');
          expect(file.existsSync(), isTrue, reason: '${s['file']}');
          expect(
            sha256.convert(file.readAsBytesSync()).toString(),
            s['sha256'],
            reason: '${s['file']}',
          );
        }
      });
    }
  });

  group('the LPE attach', () {
    test('an LPE fighter wearing a pack keeps its identity and stats', () {
      final profile = <String, dynamic>{
        'handle': 'kiro',
        'avatar': 'red hoodie',
        'cosmetics': const [],
        'archetype': 'ZODIAC_LEO',
        'aura': {'tier': 'CITIZEN'},
        'pubkey': 'ab' * 32,
      };
      final f = fighterFromLpe(profile)!;
      final binding = bindingFromManifest(
        _manifest(),
        packId: defaultPackId,
      )!;
      final worn = withPackSprite(f, binding);
      expect(worn.sprite, binding);
      expect(worn.source, 'lpe');
      expect(worn.handle, 'kiro');
      expect(worn.stats, f.stats);
      // withPackSprite with no binding is a no-op (painted stays painted).
      expect(identical(withPackSprite(f, null), f), isTrue);
    });
  });
}
