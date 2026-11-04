// Shared look for Plaza Brawler's menu screens: colours, a scrolling page that fits 360x640, big buttons,
// and a route helper that names every route (the kiosk timers read the name), the flow backdrop that keeps
// the title from flashing between Arcade steps, and the menu "select" sound on every BigButton. Real, no stubs.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../audio/sfx.dart';

class BrawlerColors {
  BrawlerColors._();
  static const bg = Color(0xFF0D0F18);
  static const panel = Color(0xFF1E293B);
  static const cyan = Color(0xFF00E5FF);
  static const gold = Color(0xFFFFD700);
  static const red = Color(0xFFFF4D6D);
}

/// A named MaterialPageRoute.
Route<T> brawlerRoute<T>(String name, WidgetBuilder builder) =>
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name),
      builder: builder,
    );

/// Pushes [page] on the app navigator as route [name].
Future<T?> pushNamedPage<T>(String name, Widget page) {
  final nav = navigatorKey.currentState;
  if (nav == null) return Future.value(null);
  return nav.push<T>(brawlerRoute<T>(name, (_) => page));
}

/// Plain dark page that sits under every Arcade / Quick Fight step (route [Routes.flow]), so going from one
/// step to the next (VS -> fight -> result -> next VS) never shows the title screen in between. A spinner
/// appears only if the gap lasts (a slow Omni Node opponent lookup).
class FlowBackdrop extends StatefulWidget {
  const FlowBackdrop({super.key});

  @override
  State<FlowBackdrop> createState() => _FlowBackdropState();
}

class _FlowBackdropState extends State<FlowBackdrop> {
  Timer? _timer;
  bool _spinner = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _spinner = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrawlerColors.bg,
      body: Center(
        child: _spinner
            ? const CircularProgressIndicator(color: BrawlerColors.cyan)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Dark page with an optional app bar; the body scrolls and is capped at 480 dp wide.
class BrawlerPage extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool showBack;
  final List<Widget>? actions;

  const BrawlerPage({
    super.key,
    this.title,
    required this.child,
    this.showBack = true,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrawlerColors.bg,
      appBar: title == null
          ? null
          : AppBar(
              backgroundColor: BrawlerColors.panel,
              automaticallyImplyLeading: showBack,
              iconTheme: const IconThemeData(color: BrawlerColors.cyan),
              title: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title!,
                  style: const TextStyle(
                    color: BrawlerColors.cyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              actions: actions,
            ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: c.maxHeight > 32 ? c.maxHeight - 32 : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width menu button, at least 52 dp tall.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final IconData? icon;

  const BigButton(
    this.label, {
    super.key,
    this.onPressed,
    this.color = BrawlerColors.cyan,
    this.textColor = Colors.black,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: textColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: onPressed == null
              ? null
              : () {
                  sfx.select();
                  onPressed!();
                },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.2,
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

/// Small rounded label ("OmniMind", "Offline", "LPE").
class SourceChip extends StatelessWidget {
  final String text;
  final bool live;
  const SourceChip(this.text, {super.key, this.live = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: live ? Colors.greenAccent : Colors.white38),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: live ? Colors.greenAccent : Colors.white70,
          fontSize: 11,
        ),
      ),
    );
  }
}
