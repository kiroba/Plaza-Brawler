import 'package:flutter/material.dart';
import '../net/omni_node.dart';
import '../npc/omnimind.dart';
import 'menu_screen.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String statusText = 'Initializing Omni Node IPC Bridge...';
  Color statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  Future<void> _initializeGame() async {
    await omniNode.loadSettings();
    await omniNode.loadIdentity();
    final conn = await omniNode.checkConnection();
    if (!mounted) return;
    setState(() {
      statusText = '${omniNode.statusWords}\nLoading fighters...';
      statusColor = conn.connected ? Colors.greenAccent : Colors.orangeAccent;
    });

    final userLpe = await omniNode.fetchUserLPE();
    final offlineOpp = await omniMind.generateOpponentNPC(sign: 'Scorpio');
    final oppLpe = await omniNode.fetchPlazaOpponent(offlineOpp);
    omniMind.currentOpponent = oppLpe;   // the fight AI reads its behaviour weights from here

    GameData.userLPE = userLpe;
    GameData.opponentLPE = oppLpe;
    if (!mounted) return;
    setState(() => statusText = '${omniNode.statusWords}\n${omniNode.fightersWords}');

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MenuScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F18),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 280,
              height: 140,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E5FF), width: 2),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'THE OMNIVERSE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00E5FF),
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'FLUTTER STUDIO • DECENTRALIZED MMORPG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameData {
  static Map<String, dynamic> userLPE = {};
  static Map<String, dynamic> opponentLPE = {};
}
