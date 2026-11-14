// Plaza Brawler entry: Boot -> Title. The app's navigator key and route observer drive the kiosk timers,
// and every pointer-down anywhere counts as activity for them (lib/app_state.dart).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_core_ui/omni_core_ui.dart'
    show OmniOta, StargateIdentity;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_state.dart';
import 'net/brawler_seed_store.dart';
import 'net/omni_node.dart' show omniNode;
import 'screens/boot_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop (D2): sqflite has no platform channel on Windows/Linux/macOS, so swap in the FFI
  // database factory before anything opens a database. This one global covers both BrawlerDb
  // (high scores + feedback) and Omni-Core-UI's event store, which share sqflite's factory.
  // Android is untouched: it keeps the platform sqflite factory. In-app updates need no guard
  // here either: OmniOta.checkAndPrompt already returns early off Android (Core-UI v0.1.3).
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // One person, one key: share the identity seed with the LPE app (same
  // secure-storage key), so the Halo saved in LPE is the fighter here.
  StargateIdentity.seedStore = BrawlerSeedStore();
  // Landscape only, for every screen (the manifest also starts the activity in landscape), so the phone
  // no longer turns between the VS card and each fight.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Updates: ask the Omni Node on this phone first, with the token saved in Settings (loaded at boot).
  OmniOta.localTokenProvider = () => omniNode.otaToken;
  runApp(const PlazaBrawlerApp());
}

class PlazaBrawlerApp extends StatelessWidget {
  const PlazaBrawlerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plaza Brawler',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [appState.routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => appState.kiosk.noteActivity(),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const BootScreen(),
    );
  }
}
