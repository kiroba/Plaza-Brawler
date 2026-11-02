import 'package:flutter/material.dart';
import 'menu_screen.dart';
import 'fighter_screen.dart';

class GameOverScreen extends StatelessWidget {
  final bool won;

  const GameOverScreen({super.key, required this.won});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F18),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              won ? 'VICTORY!' : 'DEFEAT',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: won ? const Color(0xFF00FF66) : const Color(0xFFFF3300),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              won ? 'User LPE Triumphed over OmniMind NPC' : 'OmniMind NPC Overwhelmed the Arena',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 40),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const FighterScreen()),
                    );
                  },
                  child: const Text('REPLAY BRAWL'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const MenuScreen()),
                      (route) => false,
                    );
                  },
                  child: const Text('MAIN MENU'),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
