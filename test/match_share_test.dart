// Match share stub (spec 5.3): saves locally, never claims a share.
import 'package:plaza_brawler/net/match_share.dart';
import 'package:test/test.dart';

const _summary = {
  'mode': 'arcade',
  'winner': 'p1',
  'rounds': [{}, {}],
  'duration_ms': 61000,
  'p1': {'sign': 'aries', 'source': 'lpe'},
  'p2': {'sign': 'scorpio', 'source': 'omnimind'},
};

void main() {
  test('saved locally; never "shared"', () async {
    final saved = <Map<String, dynamic>>[];
    final s = MatchShare(
      saveLocal: (m) async {
        saved.add(m);
        return true;
      },
    );
    expect(await s.shareMatch(_summary), ShareResult.savedLocalOnly);
    s.shareEnabled = true;
    expect(await s.shareMatch(_summary), ShareResult.nodeTooOld);
    expect(saved.length, 2);
    expect(
      s.statusLine(),
      'Saved on this phone; sharing needs a newer Omni Node',
    );
    expect(MatchShare.words(ShareResult.nodeTooOld), matchShareStatus);
  });

  test('no saver or a failing saver -> notSaved, never throws', () async {
    expect(await MatchShare().shareMatch(_summary), ShareResult.notSaved);
    final boom = MatchShare(saveLocal: (_) async => throw StateError('db'));
    expect(await boom.shareMatch(_summary), ShareResult.notSaved);
    expect(
      await MatchShare(saveLocal: (_) async => false).shareMatch(_summary),
      ShareResult.notSaved,
    );
  });

  test('payload has the spec 5.3 fields', () {
    final p = MatchShare.payloadFrom(
      _summary,
      appVersion: '5.4.0',
      score: 1200,
    );
    expect(p, {
      'game': 'plaza_brawler',
      'mode': 'arcade',
      'p1_sign': 'aries',
      'p2_sign': 'scorpio',
      'p2_source': 'omnimind',
      'winner': 'p1',
      'rounds': 2,
      'score': 1200,
      'duration_ms': 61000,
      'app_version': '5.4.0',
    });
  });
}
