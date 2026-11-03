// Plaza Brawler entry: Boot -> Title. The app's navigator key and route observer drive the kiosk timers,
// and every pointer-down anywhere counts as activity for them (lib/app_state.dart).
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/boot_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
