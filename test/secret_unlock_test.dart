// Secret unlock (Slice 2, flutter test): the boss-win flag persists in
// secure storage across AppState instances, and character select shows the
// secret slot locked until the win and open after it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plaza_brawler/app_state.dart';
import 'package:plaza_brawler/screens/character_select_screen.dart';

const _kBossBeaten = 'plaza_brawler_boss_beaten_v1';

/// In-memory flutter_secure_storage: the MethodChannel the plugin uses.
Future<Object?> _storageHandler(
  Map<String, String> store,
  MethodCall call,
) async {
  final args = call.arguments is Map ? call.arguments as Map : const {};
  final key = args['key'] as String?;
  switch (call.method) {
    case 'read':
      return store[key];
    case 'write':
      if (key != null) store[key] = (args['value'] as String?) ?? '';
      return null;
    case 'delete':
      store.remove(key);
      return null;
    case 'deleteAll':
      store.clear();
      return null;
    case 'readAll':
      return Map<String, String>.from(store);
    default:
      return null;
  }
}

void main() {
  group('boss-win flag persistence', () {
    late Map<String, String> store;

    setUp(() {
      store = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter_secure_storage'),
            (call) => _storageHandler(store, call),
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter_secure_storage'),
            null,
          );
    });

    test('a boss win survives a fresh AppState load', () async {
      final first = AppState();
      await first.load();
      expect(first.bossBeaten, isFalse);

      await first.markBossBeaten();
      expect(first.bossBeaten, isTrue);
      expect(store[_kBossBeaten], '1');

      final second = AppState();
      await second.load();
      expect(second.bossBeaten, isTrue);

      // Marking again is a no-op, not a second write.
      await second.markBossBeaten();
      expect(store[_kBossBeaten], '1');
    });
  });

  group('character select gate', () {
    testWidgets('locked slot shows ??? and cannot be chosen', (
      tester,
    ) async {
      appState.bossBeaten = false;
      addTearDown(() => appState.bossBeaten = false);
      await tester.pumpWidget(
        const MaterialApp(
          home: CharacterSelectScreen(
            title: 'CHOOSE YOUR FIGHTER',
            preselected: 'creepyman',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('???'), findsOneWidget);
      expect(find.text('The Creepy Man'), findsNothing);
      expect(find.text('A SECRET FIGHTER'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('???'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unlocked slot shows The Creepy Man', (tester) async {
      appState.bossBeaten = true;
      addTearDown(() => appState.bossBeaten = false);
      await tester.pumpWidget(
        const MaterialApp(
          home: CharacterSelectScreen(
            title: 'CHOOSE YOUR FIGHTER',
            preselected: 'creepyman',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('The Creepy Man'), findsOneWidget);
      expect(find.text('CHOOSE THE CREEPY MAN'), findsOneWidget);
      expect(find.text('???'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
