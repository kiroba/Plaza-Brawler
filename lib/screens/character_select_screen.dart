// Character select (spec 4.5, 5.1). Real: the 12 signs from the offline zodiac table (same stats as the
// daemon), tap to pick; the pick is saved on this phone by the caller because the LPE profile has no sign.
// With an LPE profile the player keeps their handle and aura colour and picks a fighting style (sign).
// Opponent mode adds the Ophiuchus boss and, when the node's plaza has someone, a "Plaza challenger".
import 'package:flutter/material.dart';

import '../art/fighter_painter.dart';
import '../audio/sfx.dart';
import '../game/fighter.dart';
import '../npc/zodiac_offline.dart';
import '../net/omni_node.dart';
import 'brawler_ui.dart';

class CharacterSelectScreen extends StatelessWidget {
  final String title;
  final String? preselected;
  final bool opponentMode;
  final FighterDef? plaza;

  const CharacterSelectScreen({
    super.key,
    required this.title,
    this.preselected,
    this.opponentMode = false,
    this.plaza,
  });

  @override
  Widget build(BuildContext context) {
    final roster = <FighterDef>[
      if (opponentMode && plaza != null) plaza!,
      ...offlineRoster(),
      if (opponentMode) bossFighter(),
    ];
    final handle = omniNode.lpeProfile == null
        ? null
        : omniNode.playerFighter('aries')?.handle;
    return BrawlerPage(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!opponentMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                handle != null
                    ? 'Your LPE fighter $handle: pick a fighting style.'
                    : 'Pick your sign. Each one fights differently.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 420 ? 4 : 3;
              final w = (c.maxWidth - (cols - 1) * 8) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in roster)
                    SizedBox(
                      width: w,
                      child: _Tile(
                        def: f,
                        selected: !opponentMode && f.sign == preselected,
                        onTap: () {
                          sfx.select();
                          Navigator.of(context)
                              .pop(f.source == 'plaza' ? 'plaza' : f.sign);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final FighterDef def;
  final bool selected;
  final VoidCallback onTap;
  const _Tile({required this.def, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(def.primary);
    final label = def.source == 'plaza'
        ? 'Plaza challenger'
        : (def.isBoss ? 'Ophiuchus (boss)' : def.signTitle);
    return Material(
      color: BrawlerColors.panel,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? BrawlerColors.gold
                  : color.withValues(alpha: 0.7),
              width: selected ? 3 : 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FighterPortrait(def: def, size: 60),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  def.source == 'plaza'
                      ? (def.handle ?? def.name)
                      : def.element.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'P${def.stats.power} A${def.stats.agility} W${def.stats.wit} R${def.stats.resolve}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
