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
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../art/fighter_painter.dart';
import '../audio/sfx.dart';
import '../game/fighter.dart';
import '../game/specials.dart';
import '../npc/houses.dart';
import '../npc/secret_fighters.dart';
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

  /// Whether the boss win has unlocked the secret fighter (read once here;
  /// the screen is rebuilt fresh on every visit, so a win since last time
  /// is picked up).
  late final bool _unlocked;

  @override
  void initState() {
    super.initState();
    _unlocked = appState.bossBeaten;
    _roster = <FighterDef>[
      if (widget.opponentMode && widget.plaza != null) widget.plaza!,
      if (widget.opponentMode) ...offlineRoster(),
      if (widget.opponentMode) bossFighter(),
      // Player mode: the 12 signs plus the creepy man last — locked (a
      // '???' card) until the boss win, never hidden, so the goal is visible.
      if (!widget.opponentMode) ...playerRoster(),
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

  /// True when [f] is the secret fighter and the boss win hasn't unlocked
  /// him yet.
  bool _locked(FighterDef f) => isSecretLocked(f, bossBeaten: _unlocked);

  void _spinTo(int virtualPage) {
    _controller.animateToPage(
      virtualPage,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _choose(FighterDef f) {
    if (_locked(f)) return; // a locked card is display-only: no sound, no pop
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
    // A phone in landscape is only ~360 dp tall: the stacked layout
    // (carousel + dossier + button) runs off the bottom, so the dossier
    // and the CHOOSE button sit below the fold. Short screens get the
    // side-by-side layout — carousel left, dossier + button right — so the
    // whole screen fits at rest. BrawlerPage's scroll view stays as the
    // fallback for anything still taller.
    final shortScreen = MediaQuery.sizeOf(context).height < 520;
    return BrawlerPage(
      title: widget.title,
      child: shortScreen
          ? _buildShort(context, current, color, handle)
          : _buildStacked(current, color, handle),
    );
  }

  /// The roomy layout: header, carousel, dossier, button, stacked.
  /// Sized to fit an 800 dp tall screen at rest (Nov 26: the 236 dp
  /// carousel + roomy gaps ran 34 dp past the fold): carousel 196, gaps
  /// tightened. The page stays scrollable for anything still taller.
  Widget _buildStacked(FighterDef current, Color color, String? handle) {
    return Column(
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
        const SizedBox(height: 6),
        _carousel(196),
        const SizedBox(height: 8),
        _DetailPanel(def: current, accent: color, locked: _locked(current)),
        const SizedBox(height: 10),
        _chooseButton(color, current),
      ],
    );
  }

  /// The short-screen layout: one header line, then the carousel beside
  /// the dossier + button, sized to the height BrawlerPage leaves us so
  /// the whole screen fits at rest.
  Widget _buildShort(
    BuildContext context,
    FighterDef current,
    Color color,
    String? handle,
  ) {
    final media = MediaQuery.of(context);
    // The height BrawlerPage leaves for content: the screen minus the app
    // bar, the safe-area insets, and BrawlerPage's own compact padding
    // (10 dp each side on a short screen).
    final contentHeight = media.size.height -
        kToolbarHeight -
        media.padding.top -
        media.padding.bottom -
        20;
    // One header line only on a short screen; the swipe hint goes — the
    // neighbours peeking in from the edges already say "swipe".
    final hasHeader = !widget.opponentMode;
    final headerHeight = hasHeader ? 24.0 : 0.0;
    final rowHeight = math.max(160.0, contentHeight - headerHeight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasHeader)
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
        SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _carousel(rowHeight)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The dossier scrolls inside the row only if it is
                    // still taller than the row (a long temperament on a
                    // very short screen); the button always stays put.
                    Expanded(
                      child: SingleChildScrollView(
                        child: _DetailPanel(
                          def: current,
                          accent: color,
                          locked: _locked(current),
                          compact: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _chooseButton(color, current, compact: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The infinity-scroll carousel at [height]: the roster wraps forever,
  /// neighbours peek in from the edges, the centered fighter is the pick.
  Widget _carousel(double height) {
    return SizedBox(
      height: height,
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
                locked: _locked(f),
                onTap: () =>
                    dist == 0 ? _choose(f) : _spinTo(virtual),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The CHOOSE / FIGHT button for the centered fighter.
  Widget _chooseButton(
    Color color,
    FighterDef current, {
    bool compact = false,
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
      ),
      onPressed: _locked(current) ? null : () => _choose(current),
      child: Text(
        _locked(current)
            ? '??? — BEAT OPHIUCHUS TO UNLOCK'
            : widget.opponentMode
                ? 'FIGHT THE ${_label(current).toUpperCase()}'
                : 'CHOOSE ${_label(current).toUpperCase()}',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  String _label(FighterDef f) => f.source == 'plaza'
      ? 'Plaza challenger'
      : (isSecretFighter(f)
          ? (_locked(f) ? '???' : f.name)
          : (f.isBoss ? 'Ophiuchus (boss)' : f.signTitle));
}

class _CarouselCard extends StatelessWidget {
  final FighterDef def;
  final bool centered;

  /// The secret fighter before the boss win: a '???' card that shows
  /// nothing of who he is (no portrait, no stats, no name).
  final bool locked;
  final VoidCallback onTap;
  const _CarouselCard({
    required this.def,
    required this.centered,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(def.primary);
    final label = def.source == 'plaza'
        ? 'Plaza challenger'
        : (isSecretFighter(def)
            ? (locked ? '???' : def.name)
            : (def.isBoss ? 'Ophiuchus (boss)' : def.signTitle));
    final sub = locked
        ? 'SECRET FIGHTER'
        : def.source == 'plaza'
            ? (def.handle ?? def.name)
            : isSecretFighter(def)
                ? '${def.element.toUpperCase()} · ${_cap(def.archetype)}'
                : '${_glyphs[def.sign] ?? ''} ${def.element.toUpperCase()} · ${_cap(def.archetype)}${houseOf(def.sign) == null ? '' : ' · ${houseOf(def.sign)!.title}'}';
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
                locked
                    ? const SizedBox(
                        width: 132,
                        height: 132,
                        child: Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                    : FighterPortrait(def: def, size: 132),
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
                  sub,
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

  /// The secret fighter before the boss win: no dossier at all, only the
  /// unlock criterion.
  final bool locked;

  /// Tightens padding and gaps so the dossier fits beside the carousel
  /// on a short (landscape) screen.
  final bool compact;
  const _DetailPanel({
    required this.def,
    required this.accent,
    required this.locked,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          14,
          compact ? 8 : 10,
          14,
          compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: BrawlerColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A SECRET FIGHTER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            const Text(
              'Beat Ophiuchus, the 13th Sign, to unlock this fighter. '
              'Win an arcade run to reveal who waits behind the boss.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }
    final s = def.stats;
    final personality = def.source == 'plaza'
        ? 'A challenger from your plaza. No dossier — yet.'
        : 'The ${_cap(def.archetype)} — ${def.temperament.join(', ')}.';
    // The house this fighter wears (its shade sits last in the temperament),
    // and the sign's raw stats the house nudged away from.
    final house = houseOf(def.sign);
    final base = zodiacTable[def.sign]?.stats;
    final wearsHouse = house != null &&
        base != null &&
        def.temperament.isNotEmpty &&
        def.temperament.last == house.shade;
    return Container(
      padding: EdgeInsets.fromLTRB(14, compact ? 8 : 10, 14, compact ? 8 : 10),
      decoration: BoxDecoration(
        color: BrawlerColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wearsHouse)
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 6 : 8),
              child: Text(
                '${_glyphs[def.sign] ?? ''} ${def.signTitle} · ${house.title} — ${house.domain}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          if (def.source != 'plaza')
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 6 : 8),
              child: Text(
                def.isBoss
                    ? 'ALL ELEMENTS'
                    : '${def.element.toUpperCase()} — ${Specials.forElement(def.element).name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(Specials.colorOf(def.element)),
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          _StatBar(
            label: 'Power',
            value: s.power,
            base: wearsHouse ? base.power : null,
            color: accent,
            compact: compact,
          ),
          _StatBar(
            label: 'Agility',
            value: s.agility,
            base: wearsHouse ? base.agility : null,
            color: accent,
            compact: compact,
          ),
          _StatBar(
            label: 'Wit',
            value: s.wit,
            base: wearsHouse ? base.wit : null,
            color: accent,
            compact: compact,
          ),
          _StatBar(
            label: 'Resolve',
            value: s.resolve,
            base: wearsHouse ? base.resolve : null,
            color: accent,
            compact: compact,
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            personality,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          SizedBox(height: compact ? 0 : 2),
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

  /// The sign's raw value before its house nudge (null = no house shown);
  /// a difference renders as a +1 / -1 marker beside the effective value.
  final int? base;
  final Color color;

  /// Tightens the row so the dossier fits beside the carousel on a
  /// short (landscape) screen.
  final bool compact;
  const _StatBar({
    required this.label,
    required this.value,
    this.base,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 1.5 : 2.0),
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
            width: 38,
            child: Text(
              base == null || base == value
                  ? '$value'
                  : '$value ${value > base! ? '+1' : '-1'}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: base == null || base == value
                    ? Colors.white
                    : (value > base! ? Colors.greenAccent : Colors.redAccent),
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
