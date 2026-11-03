// The player's fighter from an LPE profile (spec 5.1). Pure Dart.
import 'package:plaza_brawler/net/lpe_client.dart';
import 'package:plaza_brawler/net/lpe_fighter.dart';
import 'package:test/test.dart';

const _pk = 'aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11';

/// Shaped like daemon 8.25's avatar_view (no zodiac field).
Map<String, dynamic> _profile({Map<String, dynamic> extra = const {}}) => {
  'pubkey': _pk,
  'handle': 'kiro',
  'handle_display': '@kiro.aa11',
  'avatar': 'red hoodie',
  'cosmetics': const [],
  'aura': {
    'score': 300,
    'tier': 'CITIZEN',
    'aura_color_hex': '#3A86EF',
    'secondary_glow_hex': '#4CC9F0',
  },
  'xp': 120,
  ...extra,
};

void main() {
  test('no profile -> null', () {
    expect(fighterFromLpe(null, chosenSign: 'aries'), isNull);
  });

  test('profile without a sign needs the player pick', () {
    expect(fighterFromLpe(_profile()), isNull);
    final f = fighterFromLpe(_profile(), chosenSign: 'Leo')!;
    expect(f.source, 'lpe');
    expect(f.sign, 'leo');
    expect(f.name, '@kiro.aa11');
    expect(f.handle, '@kiro.aa11');
    expect(f.auraTier, 'CITIZEN');
    expect(f.id, 'lpe_aa11aa11aa11');
    expect(f.primary, 0xFF3A86EF);
    expect(f.layers.firstWhere((l) => l.layer == 'aura').tint, 0xFF3A86EF);
    expect(f.stats.power, 8); // leo base stats
  });

  test('an explicit sign field in the profile wins over the pick', () {
    final f = fighterFromLpe(
      _profile(extra: {'archetype': 'ZODIAC_PISCES'}),
      chosenSign: 'leo',
    )!;
    expect(f.sign, 'pisces');
    expect(
      fighterFromLpe(_profile(extra: {'zodiac': 'Taurus'}))!.sign,
      'taurus',
    );
    expect(fighterFromLpe(_profile(), chosenSign: 'ophiuchus'), isNull);
  });

  test('status lines', () {
    expect(
      lpeStatusLine(_profile(), nodeConnected: true),
      'Connected: @kiro.aa11 (aura tier CITIZEN)',
    );
    expect(lpeStatusLine(null, nodeConnected: true), lpeNoProfile);
    expect(lpeStatusLine(null, nodeConnected: false), needsNode825);
  });
}
