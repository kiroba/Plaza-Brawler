// Boot (spec 4.10). Real: loads saved settings and this install's Ed25519 identity, checks Omni Node
// (node-health on :9100), reads the player's LPE profile (daemon 8.25+) and probes OmniMind (8.26+), then
// opens the title. Everything is optional: with no node the game boots fully offline.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../net/omni_node.dart';
import 'brawler_ui.dart';
import 'title_screen.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String statusText = 'Starting...';
  Color statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await appState.load();
    await omniNode.loadSettings();
    await omniNode.loadIdentity();
    final conn = await omniNode.checkConnection();
    if (!mounted) return;
    setState(() {
      statusText = '${omniNode.statusWords}\nLoading fighters...';
      statusColor = conn.connected ? Colors.greenAccent : Colors.orangeAccent;
    });
    await omniNode.refreshLpe();
    await omniNode.loadPacks();
    await omniNode.probeOmniMind();
    await appState.probeMatchSharing();
    if (!mounted) return;
    setState(
      () => statusText = '${omniNode.statusWords}\n${omniNode.fightersWords}',
    );
    appState.startKioskTimer();

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      brawlerRoute<void>(Routes.title, (_) => const TitleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrawlerColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 280,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: BrawlerColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BrawlerColors.cyan, width: 2),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PLAZA BRAWLER',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: BrawlerColors.cyan,
                          letterSpacing: 1.5,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'AN OMNIVERSE GAME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: BrawlerColors.gold,
                        ),
                      ),
                    ],
                  ),
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
      ),
    );
  }
}
