import 'package:flutter/material.dart';
import 'boot_screen.dart';
import 'fighter_screen.dart';
import 'settings_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userLPE = GameData.userLPE.isNotEmpty ? GameData.userLPE : {'archetype': 'ZODIAC_ARIES'};
    final oppLPE = GameData.opponentLPE.isNotEmpty ? GameData.opponentLPE : {'name': 'Scorpio Opponent'};

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F18),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'HALO PLAZA BRAWLER',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF00E5FF),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'LPE 2D FIGHTER • DECENTRALIZED MMORPG TEST RUN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD700),
                ),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildProfileCard(
                    'P1: END-USER LPE',
                    '[${userLPE['archetype']}]',
                    const Color(0xFFFF3300),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  ),
                  _buildProfileCard(
                    'P2: OMNIMIND LPE',
                    '[${oppLPE['name'] ?? 'Scorpio'}]',
                    const Color(0xFF4B0082),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              _buildButton(context, 'PLAY BRAWL', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FighterScreen()),
                );
              }),
              const SizedBox(height: 16),
              _buildButton(context, 'SETTINGS', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              }),
              const SizedBox(height: 16),
              _buildButton(context, 'EXIT GAME', () {
                Navigator.pop(context);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(String title, String subtitle, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, String text, VoidCallback onPressed) {
    return SizedBox(
      width: 220,
      height: 44,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: const Color(0xFF00E5FF),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}
