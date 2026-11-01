import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../net/omni_node.dart';
import '../npc/omnimind.dart';
import 'boot_screen.dart';
import 'game_over_screen.dart';

class FighterScreen extends StatefulWidget {
  const FighterScreen({super.key});

  @override
  State<FighterScreen> createState() => _FighterScreenState();
}

class _FighterScreenState extends State<FighterScreen> {
  final double arenaWidth = 640;
  final double arenaHeight = 360;

  double playerX = 180;
  double playerY = 260;
  double playerVelocityY = 0;
  int playerHp = 100;
  bool isJumping = false;

  double opponentX = 460;
  double opponentY = 260;
  int opponentHp = 100;

  Timer? _gameLoopTimer;
  bool matchOver = false;

  late Map<String, dynamic> userLPE;
  late Map<String, dynamic> opponentLPE;

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    userLPE = GameData.userLPE.isNotEmpty ? GameData.userLPE : {'archetype': 'ZODIAC_ARIES'};
    opponentLPE = GameData.opponentLPE.isNotEmpty ? GameData.opponentLPE : {'name': 'Scorpio Opponent'};

    omniNode.dispatchEvent('FIGHTER_MATCH_START', {
      'user_lpe': userLPE['archetype'],
      'opponent_lpe': opponentLPE['name']
    });

    _startGameLoop();
  }

  void _startGameLoop() {
    _gameLoopTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (matchOver) return;
      _updateGame();
    });
  }

  void _updateGame() {
    setState(() {
      if (_pressedKeys.contains(LogicalKeyboardKey.keyA) || _pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) {
        playerX = (playerX - 4).clamp(30.0, arenaWidth - 30);
      }
      if (_pressedKeys.contains(LogicalKeyboardKey.keyD) || _pressedKeys.contains(LogicalKeyboardKey.arrowRight)) {
        playerX = (playerX + 4).clamp(30.0, arenaWidth - 30);
      }
      if ((_pressedKeys.contains(LogicalKeyboardKey.keyW) || _pressedKeys.contains(LogicalKeyboardKey.arrowUp)) && !isJumping) {
        playerVelocityY = -12;
        isJumping = true;
      }

      if (isJumping) {
        playerY += playerVelocityY;
        playerVelocityY += 0.8;
        if (playerY >= 260) {
          playerY = 260;
          isJumping = false;
          playerVelocityY = 0;
        }
      }

      final aiAction = omniMind.computeAction(opponentX, playerX, opponentHp.toDouble());
      if (aiAction['move'] == 'WALK') {
        final dir = (aiAction['dir'] as num).toDouble();
        opponentX = (opponentX + dir * 2).clamp(30.0, arenaWidth - 30);
      }
      if (aiAction['attack'] == true && (opponentX - playerX).abs() < 70) {
        if (DateTime.now().millisecond % 30 == 0) {
          _executePunch('OPPONENT');
        }
      }
    });
  }

  void _movePlayer(double delta) {
    if (matchOver) return;
    setState(() {
      playerX = (playerX + delta).clamp(30.0, arenaWidth - 30);
    });
  }

  void _jumpPlayer() {
    if (matchOver || isJumping) return;
    setState(() {
      playerVelocityY = -12;
      isJumping = true;
    });
  }

  void _playerPunch() {
    if (matchOver) return;
    _executePunch('PLAYER');
  }

  void _executePunch(String attackerType) {
    final dist = (playerX - opponentX).abs();
    if (dist < 80) {
      const dmg = 15;
      setState(() {
        if (attackerType == 'PLAYER') {
          opponentHp = (opponentHp - dmg).clamp(0, 100);
        } else {
          playerHp = (playerHp - dmg).clamp(0, 100);
        }
      });

      omniNode.dispatchEvent('FIGHTER_HIT', {
        'attacker': attackerType,
        'damage': dmg,
        'p1_hp': playerHp,
        'p2_hp': opponentHp,
      });

      if (playerHp <= 0 || opponentHp <= 0) {
        _endMatch(playerHp > 0);
      }
    }
  }

  void _endMatch(bool playerWon) {
    if (matchOver) return;
    matchOver = true;
    _gameLoopTimer?.cancel();

    omniNode.dispatchEvent('FIGHTER_MATCH_END', {
      'winner': playerWon ? 'PLAYER' : 'OPPONENT',
      'user_hp': playerHp,
      'opp_hp': opponentHp,
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => GameOverScreen(won: playerWon)),
      );
    });
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          _pressedKeys.add(event.logicalKey);
          if (event.logicalKey == LogicalKeyboardKey.space) {
            _playerPunch();
          }
        } else if (event is KeyUpEvent) {
          _pressedKeys.remove(event.logicalKey);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F18),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('PLAZA BRAWLER ARENA', style: TextStyle(color: Color(0xFF00E5FF))),
          iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('P1: USER LPE [${userLPE['archetype']}]',
                          style: const TextStyle(color: Color(0xFFFF3300), fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        height: 14,
                        child: LinearProgressIndicator(
                          value: playerHp / 100,
                          backgroundColor: Colors.grey[800],
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('P2: OMNIMIND [${opponentLPE['name'] ?? 'Scorpio'}]',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        height: 14,
                        child: LinearProgressIndicator(
                          value: opponentHp / 100,
                          backgroundColor: Colors.grey[800],
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: arenaWidth,
                  height: arenaHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: Container(color: const Color(0xFF1E293B)),
                      ),
                      Positioned(
                        left: playerX - 32,
                        top: playerY - 32,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Icon(Icons.flash_on, color: Color(0xFFFFD700)),
                          ),
                        ),
                      ),
                      Positioned(
                        left: opponentX - 32,
                        top: opponentY - 32,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4B0082),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Icon(Icons.shield, color: Color(0xFF00E5FF)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E293B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () => _movePlayer(-20),
                        child: const Text('◄', style: TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _movePlayer(20),
                        child: const Text('►', style: TextStyle(fontSize: 18)),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _jumpPlayer,
                    child: const Text('JUMP [W]', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3300), foregroundColor: Colors.white),
                    onPressed: _playerPunch,
                    child: const Text('PUNCH [SPC]', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
