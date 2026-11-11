// Character select (spec 4.5, 5.1), redesigned Nov 11 (design drop
// 2026-11-10): a side-by-side horizontal INFINITY SCROLL — the roster wraps
// forever, neighbours peek in from the edges, and the centered fighter is
// the pick. Portraits are big, stats are LABELLED (not the old bare-letter
// grid "P6 A9 W6 R5"), and every fighter shows its personality: the
// archetype + temperament that already live in the zodiac table, plus the
// taunt line as its voice. Pure presentation: picking still returns the
// same String contract as the old grid (the sign, or 'plaza'), and no
// MatchEngine code changes.
// With an LPE profile the player keeps their handle and aura colour and
// picks a fighting style (sign). Opponent mode adds the Ophiuchus boss
// and, when the node's plaza has someone, a "Plaza challenger".
import 'package:flutter/material.dart';

import '../art/fighter_painter.dart';
import '../audio/sfx.dart';
import '../game/fighter.dart';
import '../npc/zodiac_offline.dart';
import '../net/omni_node.dart';
import 'brawler_ui.dart';

const Map<String, String> _glyphs = {
  'aries': '♈',
  'taurus': '♉',
  'gemini': '♊',
  'cancer': '♋',
  'leo': '♌',
  'virgo': '♍',
  'libra': '♎',
  'scorpio': '♏',
  'sagittarius': '♐',
  'capricorn': '♑',
  'aquarius': '♒',
  'pisces': '♓',
  'ophiuchus': '⛎',
};

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class CharacterSelectScreen extends StatefulWidget {
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
  State<CharacterSelectScreen> createState() => _CharacterSelectScreenState();
}

class _CharacterSelectScreenState extends State<CharacterSelectScreen> {
  // One virtual page per lap around the roster; the wheel starts many laps
  // in, on the preselected fighter, so it can spin either way forever.
  static const int _laps = 1000;

  late final List<FighterDef> _roster;
  late final PageController _controller;
  late int _center;

  @override
  void initState() {
    super.initState();
    _roster = <FighterDef>[
      if (widget.opponentMode && widget.plaza != null) widget.plaza!,
      ...offlineRoster(),
      if (widget.opponentMode) bossFighter(),
    ];
    var start = 0;
    if (!widget.opponentMode && widget.preselected != null) {
      final i = _roster.indexWhere((f) => f.sign == widget.preselected);
      if (i >= 0) start = i;
    }
    _center = _laps * _roster.length + start;
    _controller = PageController(
      viewportFraction: 0.62,
      initialPage: _center,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  FighterDef get _current => _roster[_center % _roster.length];

  void _spinTo(int virtualPage) {
    _controller.animateToPage(
      virtualPage,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _choose(FighterDef f) {
    sfx.select();
    Navigator.of(context).pop(f.source == 'plaza' ? 'plaza' : f.sign);
  }

  @override
  Widget build(BuildContext context) {
    final handle = omniNode.lpeProfile == null
        ? null
        : omniNode.playerFighter('aries')?.handle;
    final current = _current;
    final color = Color(current.primary);
    return BrawlerPage(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.opponentMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                handle != null
                    ? 'Your LPE fighter $handle: pick a fighting style.'
                    : 'Pick your sign. Each one fights differently.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          const Text(
            '◀  SWIPE — TAP THE CENTER FIGHTER TO CHOOSE  ▶',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 236,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (p) => setState(() => _center = p),
              itemBuilder: (context, virtual) {
                final f = _roster[virtual % _roster.length];
                final dist = (virtual - _center).abs();
                final focus = dist == 0 ? 1.0 : (dist == 1 ? 0.82 : 0.7);
                return AnimatedScale(
                  scale: focus,
                  duration: const Duration(milliseconds: 220),
                  child: AnimatedOpacity(
                    opacity: dist == 0 ? 1.0 : 0.55,
                    duration: const Duration(milliseconds: 220),
                    child: _CarouselCard(
                      def: f,
                      centered: dist == 0,
                      onTap: () =>
                          dist == 0 ? _choose(f) : _spinTo(virtual),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _DetailPanel(def: current, accent: color),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _choose(current),
            child: Text(
              widget.opponentMode
                  ? 'FIGHT THE ${_label(current).toUpperCase()}'
                  : 'CHOOSE ${_label(current).toUpperCase()}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _label(FighterDef f) => f.source == 'plaza'
      ? 'Plaza challenger'
      : (f.isBoss ? 'Ophiuchus (boss)' : f.signTitle);
}

class _CarouselCard extends StatelessWidget {
  final FighterDef def;
  final bool centered;
  final VoidCallback onTap;
  const _CarouselCard({
    required this.def,
    required this.centered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(def.primary);
    final label = def.source == 'plaza'
        ? 'Plaza challenger'
        : (def.isBoss ? 'Ophiuchus (boss)' : def.signTitle);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Material(
        color: BrawlerColors.panel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.35), BrawlerColors.panel],
                stops: const [0.0, 0.75],
              ),
              border: Border.all(
                color: centered ? BrawlerColors.gold : color,
                width: centered ? 3 : 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FighterPortrait(def: def, size: 132),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                Text(
                  def.source == 'plaza'
                      ? (def.handle ?? def.name)
                      : '${_glyphs[def.sign] ?? ''} ${def.element.toUpperCase()} · ${_cap(def.archetype)}',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The centered fighter's dossier: labelled stat bars and its personality.
class _DetailPanel extends StatelessWidget {
  final FighterDef def;
  final Color accent;
  const _DetailPanel({required this.def, required this.accent});

  @override
  Widget build(BuildContext context) {
    final s = def.stats;
    final personality = def.source == 'plaza'
        ? 'A challenger from your plaza. No dossier — yet.'
        : 'The ${_cap(def.archetype)} — ${def.temperament.join(', ')}.';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: BrawlerColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatBar(label: 'Power', value: s.power, color: accent),
          _StatBar(label: 'Agility', value: s.agility, color: accent),
          _StatBar(label: 'Wit', value: s.wit, color: accent),
          _StatBar(label: 'Resolve', value: s.resolve, color: accent),
          const SizedBox(height: 8),
          Text(
            personality,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '“${tauntFor(def)}”',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / 10,
                minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
