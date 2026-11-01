import 'package:flutter/material.dart';
import 'screens/boot_screen.dart';

void main() {
  runApp(const PlazaBrawlerApp());
}

class PlazaBrawlerApp extends StatelessWidget {
  const PlazaBrawlerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plaza Brawler LPE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00E5FF)),
        useMaterial3: true,
      ),
      home: const BootScreen(),
    );
  }
}
